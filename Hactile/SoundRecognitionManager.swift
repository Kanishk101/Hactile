//
//  SoundRecognitionManager.swift
//  Hactile
//
//  Core intelligence layer for real-time sound recognition.
//  Uses AVAudioEngine + SoundAnalysis for on-device, privacy-first audio analysis.
//
//  Design Decision: ObservableObject singleton pattern chosen because:
//  1. Sound recognition is a global system service (only one mic stream should exist)
//  2. Multiple views need to observe detection state
//  3. Lifecycle must persist across view hierarchies
//

import Foundation
import AVFoundation
import SoundAnalysis
import Combine
import UIKit
// MARK: - Type Import Note
// DetectedSoundType is defined in SharedTypes.swift
// This file uses that shared definition to avoid type ambiguity

// MARK: - Detection Event

/// Represents a confirmed sound detection with metadata
struct DetectionEvent {
    let soundType: DetectedSoundType
    let confidence: Double
    let timestamp: Date
}

// MARK: - Microphone Permission Status

enum MicrophonePermissionStatus {
    case undetermined
    case denied
    case granted
}

// MARK: - Sound Recognition Error

enum SoundRecognitionError: Error, LocalizedError {
    case microphonePermissionDenied
    case microphonePermissionRestricted
    case audioEngineFailure(Error)
    case soundAnalysisFailure(Error)
    case audioSessionConfigurationFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access was denied. Please enable it in Settings."
        case .microphonePermissionRestricted:
            return "Microphone access is restricted on this device."
        case .audioEngineFailure(let error):
            return "Audio engine failed: \(error.localizedDescription)"
        case .soundAnalysisFailure(let error):
            return "Sound analysis failed: \(error.localizedDescription)"
        case .audioSessionConfigurationFailed(let error):
            return "Audio session configuration failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Sound Recognition Manager

/// Central manager for real-time sound recognition.
///
/// ## Architecture Overview
/// ```
/// [Microphone] → [AVAudioEngine] → [SNAudioStreamAnalyzer] → [Detection Logic] → [Outputs]
///                     ↓                      ↓                       ↓
///               Input Node Tap         Classification          Confidence Gate
///                                        Results              Temporal Smoothing
///                                                                Cooldown
/// ```
///
/// ## Privacy Guarantees
/// - Audio is NEVER recorded or stored
/// - Buffers are processed and immediately discarded
/// - All analysis happens on-device using Apple's SoundAnalysis framework
///
@MainActor
final class SoundRecognitionManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SoundRecognitionManager()
    
    // MARK: - Published State
    
    /// Whether the manager is actively listening to the microphone
    @Published private(set) var isListening: Bool = false
    
    /// The most recently confirmed detection (nil if none active)
    @Published private(set) var currentDetection: DetectedSoundType?
    
    /// Current error state, if any
    @Published private(set) var currentError: SoundRecognitionError?
    
    /// Microphone permission status
    @Published private(set) var permissionStatus: MicrophonePermissionStatus = .undetermined
    
    /// Last confirmed detection confidence (0.0 - 1.0)
    @Published private(set) var currentConfidence: Double?
    
    // MARK: - Configuration
    
    /// Sound types the user has enabled for detection
    var enabledSoundTypes: Set<DetectedSoundType> = Set(DetectedSoundType.allCases)
    
    // MARK: - Detection Thresholds
    
    // Per-sound confidence thresholds are defined in DetectedSoundType.confidenceThreshold
    // This allows tuning sensitivity per sound type without changing core logic.
    
    /// Number of consecutive positive frames required to confirm a detection.
    /// Set to 1 because Apple's version1 classifier already uses a 1-second
    /// analysis window with 50% overlap, providing built-in temporal smoothing.
    /// Requiring 2+ frames means a sound must persist for ~1.5s minimum,
    /// which is too long for brief sounds like doorbell rings or single knocks.
    private let requiredConsecutiveFrames: Int = 1
    
    /// Cooldown period (in seconds) before the same sound type can trigger again.
    /// 3 seconds balances between spam prevention and catching repeat sounds
    /// (e.g. someone knocking repeatedly at the door).
    private let cooldownDuration: TimeInterval = 3.0
    
    // MARK: - Audio Pipeline Components
    
    /// Core audio engine that manages the audio graph
    private var audioEngine: AVAudioEngine?
    
    /// SoundAnalysis stream analyzer that processes audio buffers
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    
    /// The classification request sent to SoundAnalysis
    private var classificationRequest: SNClassifySoundRequest?
    
    // MARK: - Detection State Tracking
    
    /// Tracks consecutive positive detections per sound type
    /// Key: sound type, Value: count of consecutive frames above threshold
    private var consecutiveDetectionCounts: [DetectedSoundType: Int] = [:]
    
    /// Tracks the last confirmed detection time per sound type for cooldown
    /// Key: sound type, Value: timestamp of last confirmed detection
    private var lastDetectionTimes: [DetectedSoundType: Date] = [:]
    
    /// Tracks recent confidence values per sound type for smoothing
    private var confidenceHistory: [DetectedSoundType: [Double]] = [:]
    
    // MARK: - Ambient Noise Calibration
    
    /// Baseline ambient noise floor measured at start of listening session.
    /// Used as a simple amplitude gate to reduce false positives in loud environments.
    /// - If nil, calibration hasn't completed yet or failed — detection proceeds without gate.
    private var ambientNoiseFloor: Float?
    
    /// Whether calibration is currently in progress
    private var isCalibrating: Bool = false
    
    /// Accumulated RMS samples during calibration
    private var calibrationSamples: [Float] = []
    
    /// Number of buffers to collect during calibration (~1.5 seconds at typical buffer rates)
    private let calibrationBufferCount: Int = 15
    
    /// Multiplier above ambient floor required to pass the amplitude gate
    private let noiseGateMultiplier: Float = 1.3
    
    // MARK: - Simulation State
    
    /// Counter for simulated detections (for testing without microphone)
    private var simulationFrameCount: Int = 0
    private var simulatingSound: DetectedSoundType?
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        updatePermissionStatus()
        setupInterruptionObserver()
    }
    
    // MARK: - Audio Session Interruption Handling
    
    /// Observes audio session interruptions (phone calls, Siri, other apps)
    /// and automatically restarts listening when the interruption ends.
    private func setupInterruptionObserver() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioInterruption(notification)
            }
        }
    }
    
    /// Handles audio session interruption events.
    /// On interruption end with shouldResume flag, automatically restarts the audio engine.
    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            #if DEBUG
            print("SoundRecognitionManager: Audio session interrupted")
            #endif
            // Don't stop listening or set error — the engine will resume
            
        case .ended:
            #if DEBUG
            print("SoundRecognitionManager: Audio session interruption ended")
            #endif
            
            // Check if we should resume
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume), isListening {
                    // Restart the audio engine
                    do {
                        try audioEngine?.start()
                        #if DEBUG
                        print("SoundRecognitionManager: Audio engine restarted after interruption")
                        #endif
                    } catch {
                        #if DEBUG
                        print("SoundRecognitionManager: Failed to restart after interruption: \(error)")
                        #endif
                    }
                }
            }
            
        @unknown default:
            break
        }
    }
    
    // MARK: - Permission Management
    
    /// Updates the current microphone permission status
    private func updatePermissionStatus() {
        if #available(iOS 17.0, *) {
            let status = AVAudioApplication.shared.recordPermission
            permissionStatus = mapPermission(status)
        } else {
            let status = AVAudioSession.sharedInstance().recordPermission
            permissionStatus = mapLegacyPermission(status)
        }
    }
    
    /// Requests microphone permission from the user
    /// - Returns: True if permission was granted
    func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        self.updatePermissionStatus()
                        continuation.resume(returning: granted)
                    }
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    Task { @MainActor in
                        self.updatePermissionStatus()
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }

    @available(iOS 17.0, *)
    private func mapPermission(_ status: AVAudioApplication.recordPermission) -> MicrophonePermissionStatus {
        switch status {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .undetermined
        @unknown default:
            return .undetermined
        }
    }

    private func mapLegacyPermission(_ status: AVAudioSession.RecordPermission) -> MicrophonePermissionStatus {
        switch status {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .undetermined
        @unknown default:
            return .undetermined
        }
    }

    
    // MARK: - Audio Session Configuration
    
    /// Configures the audio session for sound recognition
    ///
    /// Configuration choices:
    /// - `.playAndRecord`: Allows simultaneous playback (for haptics) and recording
    /// - `.measurement`: Optimized for audio analysis, minimal processing
    /// - `.allowBluetooth`: Enables AirPods and other Bluetooth devices
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetoothHFP, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SoundRecognitionError.audioSessionConfigurationFailed(error)
        }
    }
    
    // MARK: - Start Listening
    
    /// Starts the audio pipeline and begins sound recognition
    ///
    /// ## Flow
    /// 1. Check/request microphone permission
    /// 2. Configure audio session
    /// 3. Set up AVAudioEngine with input tap
    /// 4. Create and configure SNAudioStreamAnalyzer
    /// 5. Start the engine
    func startListening() async throws {
        // Prevent multiple starts
        guard !isListening else { return }
        
        // Clear any previous error
        currentError = nil
        
        // Step 1: Check microphone permission
        updatePermissionStatus()
        
        switch permissionStatus {
        case .undetermined:
            let granted = await requestMicrophonePermission()
            guard granted else {
                let error = SoundRecognitionError.microphonePermissionDenied
                currentError = error
                throw error
            }
        case .denied:
            let error = SoundRecognitionError.microphonePermissionDenied
            currentError = error
            throw error
        case .granted:
            break
        }
        
        // Step 2: Configure audio session
        do {
            try configureAudioSession()
        } catch let error as SoundRecognitionError {
            currentError = error
            throw error
        }
        
        // Step 3: Set up audio engine
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Validate format
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            let error = SoundRecognitionError.audioEngineFailure(
                NSError(domain: "Hactile", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid audio format from input node"
                ])
            )
            currentError = error
            throw error
        }
        
        // Step 4: Create SoundAnalysis components
        let analyzer = SNAudioStreamAnalyzer(format: inputFormat)
        
        // Create classification request using Apple's built-in sound classifier
        // SNClassifierIdentifier.version1 provides recognition for hundreds of sounds
        // including doorbells, sirens, knocks, alarms, dog barks, and baby cries
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.windowDuration = CMTime(seconds: 1.0, preferredTimescale: 48000)
            request.overlapFactor = 0.5 // 50% overlap for smoother detections
            
            try analyzer.add(request, withObserver: self)
            classificationRequest = request
        } catch {
            let snError = SoundRecognitionError.soundAnalysisFailure(error)
            currentError = snError
            throw snError
        }
        
        // Step 5: Install tap on input node
        // PRIVACY: Audio buffers are passed directly to the analyzer
        // and are NEVER stored, recorded, or transmitted
        inputNode.installTap(onBus: 0, bufferSize: 8192, format: inputFormat) { [weak self] buffer, time in
            // Analyze the buffer on a background queue
            // The analyzer handles its own threading internally
            self?.analyzeBuffer(buffer, at: time, using: analyzer)
        }
        
        // Step 6: Start the engine
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            let engineError = SoundRecognitionError.audioEngineFailure(error)
            currentError = engineError
            throw engineError
        }
        
        // Store references
        audioEngine = engine
        streamAnalyzer = analyzer
        
        // Reset detection state
        resetDetectionState()
        
        // Start ambient noise calibration
        startCalibration()
        
        // Update published state
        isListening = true
    }
    
    // MARK: - Ambient Noise Calibration
    
    /// Starts the calibration process to measure ambient noise floor.
    /// Calibration runs for ~1.5 seconds, measuring RMS energy of incoming buffers.
    /// This is a simple amplitude gate — NOT ML logic — to reduce false positives.
    private func startCalibration() {
        ambientNoiseFloor = nil
        calibrationSamples = []
        isCalibrating = true
    }
    
    /// Processes a buffer during calibration to measure ambient RMS.
    /// Called from the audio tap before passing to SoundAnalysis.
    /// - Parameter buffer: The audio buffer to measure
    /// - Returns: True if calibration is complete
    private func processCalibrationBuffer(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard isCalibrating else { return true }
        
        let rms = calculateRMS(buffer)
        calibrationSamples.append(rms)
        
        if calibrationSamples.count >= calibrationBufferCount {
            // Calibration complete — compute average as noise floor
            let average = calibrationSamples.reduce(0, +) / Float(calibrationSamples.count)
            ambientNoiseFloor = average
            isCalibrating = false
            calibrationSamples = []
            
            #if DEBUG
            print("SoundRecognitionManager: Calibration complete. Noise floor: \(average)")
            #endif
            
            return true
        }
        
        return false
    }
    
    /// Calculates RMS (Root Mean Square) energy of an audio buffer.
    /// This is a simple amplitude measurement — does NOT store or retain audio data.
    /// - Parameter buffer: The audio buffer to analyze
    /// - Returns: RMS energy value
    private func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        
        let channelDataPointer = channelData[0]
        let frameLength = Int(buffer.frameLength)
        
        guard frameLength > 0 else { return 0 }
        
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelDataPointer[i]
            sum += sample * sample
        }
        
        return sqrt(sum / Float(frameLength))
    }
    
    /// Checks if the buffer's energy passes the ambient noise gate.
    /// - Parameter buffer: The audio buffer to check
    /// - Returns: True if buffer energy exceeds (noiseFloor × multiplier), or if no calibration exists
    private func passesNoiseGate(_ buffer: AVAudioPCMBuffer) -> Bool {
        // If no calibration, allow all detections (fail-safe)
        guard let noiseFloor = ambientNoiseFloor else { return true }
        
        let rms = calculateRMS(buffer)
        let threshold = noiseFloor * noiseGateMultiplier
        
        return rms > threshold
    }
    
    // MARK: - Stop Listening
    
    /// Stops the audio pipeline and releases resources
    func stopListening() {
        guard isListening else { return }
        
        // Remove the tap first to stop receiving buffers
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        // Stop the engine
        audioEngine?.stop()
        
        // Remove the classification request from the analyzer
        if let request = classificationRequest {
            streamAnalyzer?.remove(request)
        }
        
        // Clear references
        audioEngine = nil
        streamAnalyzer = nil
        classificationRequest = nil
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        
        // Reset state
        resetDetectionState()
        isListening = false
        currentDetection = nil
    }
    
    // MARK: - Buffer Analysis
    
    /// Passes an audio buffer to the SoundAnalysis stream analyzer
    /// - Parameters:
    ///   - buffer: The audio buffer from AVAudioEngine
    ///   - time: The timestamp of the buffer
    ///   - analyzer: The SNAudioStreamAnalyzer to use
    ///
    /// PRIVACY: This method processes audio in real-time and does NOT store any data
    private func analyzeBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime, using analyzer: SNAudioStreamAnalyzer) {
        // During calibration, measure ambient noise
        if isCalibrating {
            _ = processCalibrationBuffer(buffer)
        }
        
        // ALWAYS pass buffers to the analyzer.
        // Apple's SoundAnalysis handles noise filtering internally.
        // Our previous noise gate was too aggressive and was silently dropping
        // valid sounds like doorbells and knocks that barely exceeded ambient levels.
        analyzer.analyze(buffer, atAudioFramePosition: time.sampleTime)
    }
    
    // MARK: - Detection State Management
    
    /// Resets all detection tracking state
    private func resetDetectionState() {
        consecutiveDetectionCounts.removeAll()
        confidenceHistory.removeAll()
        // Reset calibration state for next session
        ambientNoiseFloor = nil
        isCalibrating = false
        calibrationSamples = []
        // Note: We don't reset lastDetectionTimes to preserve cooldowns across stop/start
    }
    
    // MARK: - Detection Logic
    
    /// Processes a classification result and determines if a sound should be confirmed
    /// - Parameters:
    ///   - soundType: The detected sound type
    ///   - confidence: The confidence value (0.0 - 1.0)
    ///
    /// ## Detection Pipeline
    /// 1. **Enabled Check**: Ignore if sound type is disabled by user
    /// 2. **Confidence Gate**: Ignore if below threshold (0.85)
    /// 3. **Temporal Smoothing**: Require consecutive positive frames
    /// 4. **Cooldown**: Prevent re-triggering within cooldown period
    private func processDetection(soundType: DetectedSoundType, confidence: Double) {
        // Step 1: Check if this sound type is enabled
        guard enabledSoundTypes.contains(soundType) else {
            return
        }
        
        // Step 2: Confidence gate
        guard confidence >= soundType.confidenceThreshold else {
            // Reset consecutive count if confidence drops below per-sound threshold
            consecutiveDetectionCounts[soundType] = 0
            confidenceHistory[soundType] = []
            return
        }
        
        // Track confidence history for smoothing (last 5 frames)
        var history = confidenceHistory[soundType] ?? []
        history.append(confidence)
        if history.count > 5 { history.removeFirst() }
        confidenceHistory[soundType] = history
        
        // Step 3: Temporal smoothing - increment consecutive count
        let currentCount = (consecutiveDetectionCounts[soundType] ?? 0) + 1
        consecutiveDetectionCounts[soundType] = currentCount
        
        // Check if we've reached the required consecutive frames
        guard currentCount >= requiredConsecutiveFrames else {
            return
        }
        
        // Step 4: Cooldown check
        if let lastTime = lastDetectionTimes[soundType] {
            let elapsed = Date().timeIntervalSince(lastTime)
            guard elapsed >= cooldownDuration else {
                return
            }
        }
        
        // All checks passed - confirm the detection!
        let smoothedConfidence = (confidenceHistory[soundType]?.reduce(0, +) ?? confidence) / Double(max(confidenceHistory[soundType]?.count ?? 1, 1))
        confirmDetection(soundType: soundType, confidence: smoothedConfidence)
    }
    
    /// Handles a confirmed sound detection
    /// - Parameters:
    ///   - soundType: The confirmed sound type
    ///   - confidence: The confidence value
    private func confirmDetection(soundType: DetectedSoundType, confidence: Double) {
        let now = Date()
        
        // Update cooldown timestamp
        lastDetectionTimes[soundType] = now
        
        // Reset consecutive count + confidence history
        consecutiveDetectionCounts[soundType] = 0
        confidenceHistory[soundType] = []
        
        // Create detection event
        let event = DetectionEvent(
            soundType: soundType,
            confidence: confidence,
            timestamp: now
        )
        
        // Update published state
        Task { @MainActor in
            self.currentDetection = soundType
            self.currentConfidence = confidence
            
            // Trigger outputs
            self.handleConfirmedDetection(event)
            
            // Clear current detection after a delay
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            if self.currentDetection == soundType {
                self.currentDetection = nil
                self.currentConfidence = nil
            }
        }
    }
    
    /// Triggers all outputs for a confirmed detection
    /// - Parameter event: The detection event
    private func handleConfirmedDetection(_ event: DetectionEvent) {
        // Trigger haptic feedback when in foreground
        HapticManager.shared.playPattern(for: mapToHapticType(event.soundType))
        
        // Start or update Live Activity for EVERY detection
        startOrUpdateLiveActivity(for: event)
        
        // Post local notification for EVERY detection (foreground and background)
        NotificationManager.shared.postDetectionNotification(for: event)
        
        #if DEBUG
        print("SoundRecognitionManager: Triggered outputs for \(event.soundType) detection")
        #endif
    }
    
    private func mapToHapticType(_ soundType: DetectedSoundType) -> HapticSoundType {
        switch soundType {
        case .doorbell: return .doorbell
        case .siren: return .siren
        case .knock: return .knock
        case .alarm: return .alarm
        case .dogBark: return .dogBark
        case .babyCry: return .babyCry
        case .carHorn: return .carHorn
        case .glassBreak: return .glassBreak
        case .gunshot: return .gunshot
        case .catMeow: return .catMeow
        case .waterRunning: return .waterRunning
        case .speech: return .speech
        case .applause: return .applause
        case .cough: return .cough
        case .whistle: return .whistle
        }
    }
    
    // MARK: - Live Activity Integration
    
    /// Starts or updates a Live Activity for the detected sound
    /// - Parameter event: The detection event
    ///
    /// Note: This is a placeholder that calls into HactileLiveActivityManager
    /// The actual implementation is in HactileLiveActivityManager.swift
    private func startOrUpdateLiveActivity(for event: DetectionEvent) {
        // Integration point for Live Activity
        HactileLiveActivityManager.shared.startActivity(
            detectedSound: event.soundType,
            confidence: event.confidence,
            location: nil
        )
    }
    
    // MARK: - Simulation Mode
    
    /// Simulates a sound detection for testing purposes
    /// - Parameter type: The sound type to simulate
    ///
    /// This method is critical for:
    /// 1. Demo purposes during Swift Student Challenge judging
    /// 2. Testing the detection pipeline without microphone access
    /// 3. Validating haptic and Live Activity integrations
    ///
    /// The simulation runs through the SAME detection logic as real detections:
    /// - Confidence threshold check
    /// - Temporal smoothing (consecutive frames)
    /// - Cooldown enforcement
    func simulateSound(_ type: DetectedSoundType) {
        // Ensure the sound type is enabled
        guard enabledSoundTypes.contains(type) else {
            return
        }
        
        // Simulate with realistic varying confidence (85% - 98%)
        // This makes the notifications show different confidence values each time
        let baseThreshold = type.confidenceThreshold
        let variationRange = (1.0 - baseThreshold) * 0.9  // Use 90% of available range above threshold
        let simulatedConfidence = baseThreshold + Double.random(in: 0...variationRange)
        let requiredFrames = self.requiredConsecutiveFrames
        
        // Use a timer to simulate multiple consecutive frames
        // This respects the temporal smoothing requirement
        simulatingSound = type
        simulationFrameCount = 0
        
        // Use Task-based simulation instead of Timer for Swift 6 compatibility
        Task { @MainActor [weak self] in
            for _ in 0..<(requiredFrames + 2) {
                guard let self = self else { return }
                guard self.simulatingSound == type else { return }
                
                self.simulationFrameCount += 1
                self.processDetection(soundType: type, confidence: simulatedConfidence)
                
                // Wait between frames
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            }
            
            // Reset simulation state
            if let self = self {
                self.simulatingSound = nil
                self.simulationFrameCount = 0
            }
        }
    }
    
    /// Cancels any ongoing simulation
    func cancelSimulation() {
        simulatingSound = nil
        simulationFrameCount = 0
    }
}

// MARK: - SNResultsObserving

extension SoundRecognitionManager: SNResultsObserving {
    
    /// Called when SoundAnalysis produces a classification result
    /// - Parameters:
    ///   - request: The classification request that produced the result
    ///   - result: The classification result containing detected sounds and confidences
    nonisolated func request(_ request: SNRequest, didProduce result: SNResult) {
        // Ensure we have a classification result
        guard let classificationResult = result as? SNClassificationResult else {
            return
        }
        
        // Process each classification in the result
        // Classifications are sorted by confidence (highest first)
        for classification in classificationResult.classifications {
            let identifier = classification.identifier
            let confidence = Double(classification.confidence)
            
            // Process on main actor for thread safety
            Task { @MainActor in
                // Try to map the classifier label to our sound types
                if let soundType = DetectedSoundType(classifierLabel: identifier) {
                    self.processDetection(
                        soundType: soundType,
                        confidence: confidence
                    )
                }
            }
        }
    }
    
    /// Called when the analysis request completes
    /// - Parameter request: The completed request
    nonisolated func requestDidComplete(_ request: SNRequest) {
        // Analysis completed (typically when stopping)
        // No action needed
    }
    
    /// Called when an error occurs during analysis
    /// - Parameters:
    ///   - request: The request that encountered an error
    ///   - error: The error that occurred
    /// Called when an error occurs during analysis.
    /// We handle this gracefully — log the error but do NOT stop listening.
    /// Transient errors (e.g. audio session interruptions) are expected and
    /// the analyzer can recover. Stopping listening + setting currentError
    /// was causing the permanent "Sound analysis failed" error state.
    nonisolated func request(_ request: SNRequest, didFailWithError error: Error) {
        #if DEBUG
        print("SoundRecognitionManager: Analysis error (non-fatal): \(error.localizedDescription)")
        #endif
        // Do NOT call stopListening() or set currentError here.
        // The analyzer will continue processing subsequent buffers.
        // Only fatal errors (like engine failure) should stop listening,
        // and those are handled in the audio engine setup.
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a sound is detected and confirmed
    static let soundDetected = Notification.Name("HactileSoundDetected")
}

// MARK: - Preview Helpers

#if DEBUG
extension SoundRecognitionManager {
    /// Creates a preview instance with mock state
    static var preview: SoundRecognitionManager {
        let manager = SoundRecognitionManager.shared
        return manager
    }
    
    /// Simulates a detection for SwiftUI previews
    func simulateDetectionForPreview(_ type: DetectedSoundType) {
        currentDetection = type
    }
}
#endif
