//
//  SoundRecognitionManager.swift
//  Hactile
//

import Foundation
import AVFoundation
import SoundAnalysis
import Combine
import UIKit

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

@MainActor
final class SoundRecognitionManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SoundRecognitionManager()
    
    /// App launch time for debug elapsed timestamps
    private let appStartTime = Date()
    
    /// Elapsed seconds since app launch
    private var elapsed: String {
        String(format: "%.1fs", Date().timeIntervalSince(appStartTime))
    }
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
    
    private let cooldownDuration: TimeInterval = 10.0
    private let globalCooldownDuration: TimeInterval = 10.0
    private var lastGlobalDetectionTime: Date?
    private var lastConfirmedSoundType: DetectedSoundType?
    
    /// Tracks recent confidence scores for ALL above-threshold candidates (timestamp, confidence)
    /// Used to detect competing/confused sound types and suppress false positives
    private var recentCandidateScores: [DetectedSoundType: [(time: Date, confidence: Double)]] = [:]
    
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
        
        // Update published state
        isListening = true
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
        // Pass all buffers to the analyzer.
        // Apple's SoundAnalysis handles noise filtering internally.
        analyzer.analyze(buffer, atAudioFramePosition: time.sampleTime)
    }
    
    // MARK: - Detection State Management
    
    /// Resets all detection tracking state
    private func resetDetectionState() {
        consecutiveDetectionCounts.removeAll()
        confidenceHistory.removeAll()
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
            let current = consecutiveDetectionCounts[soundType] ?? 0
            if current > 0 {
                consecutiveDetectionCounts[soundType] = current - 1
                #if DEBUG
                print("[\(elapsed)] ⬇️ \(soundType) conf=\(String(format: "%.3f", confidence)) < threshold=\(soundType.confidenceThreshold) | frames=\(current - 1)/\(soundType.requiredFrames)")
                #endif
            }
            return
        }
        
        // Step 3: Global cooldown — blocks OTHER sound types for 10s after any detection.
        // The SAME confirmed type is exempt (handled by per-type cooldown) so it can
        // re-fire every 10s if still playing — and each re-fire resets this global clock,
        // keeping misclassifications (e.g. phoneRinging from an alarm) permanently blocked.
        if soundType != lastConfirmedSoundType, let lastGlobal = lastGlobalDetectionTime {
            let sinceGlobal = Date().timeIntervalSince(lastGlobal)
            if sinceGlobal < globalCooldownDuration {
                #if DEBUG
                print("[\(elapsed)] 🚫 \(soundType) SKIPPED (global cooldown \(String(format: "%.1f", sinceGlobal))s < \(globalCooldownDuration)s)")
                #endif
                consecutiveDetectionCounts[soundType] = 0
                confidenceHistory[soundType] = []
                return
            }
        }
        
        // Step 4: Per-type cooldown — also checked BEFORE counting frames
        if let lastTime = lastDetectionTimes[soundType] {
            let sinceLastType = Date().timeIntervalSince(lastTime)
            if sinceLastType < cooldownDuration {
                #if DEBUG
                print("[\(elapsed)] 🚫 \(soundType) SKIPPED (per-type cooldown \(String(format: "%.1f", sinceLastType))s < \(cooldownDuration)s) — not counting frame")
                #endif
                consecutiveDetectionCounts[soundType] = 0
                return
            }
        }
        
        // Step 5: Track confidence history for smoothing (last 5 frames)
        var history = confidenceHistory[soundType] ?? []
        history.append(confidence)
        if history.count > 5 { history.removeFirst() }
        confidenceHistory[soundType] = history
        
        // Step 6: Temporal smoothing - increment consecutive count
        let newCount = (consecutiveDetectionCounts[soundType] ?? 0) + 1
        consecutiveDetectionCounts[soundType] = newCount
        
        #if DEBUG
        print("[\(elapsed)] ✅ \(soundType) conf=\(String(format: "%.3f", confidence)) threshold=\(soundType.confidenceThreshold) | frames=\(newCount)/\(soundType.requiredFrames)")
        #endif
        
        // Check if we've reached the required consecutive frames
        guard newCount >= soundType.requiredFrames else {
            return
        }
        
        // Step 7: Competing candidate check — suppress false positives using dominance rules
        // Uses explicit dominance pairs to resolve known classifier confusions
        let now = Date()
        let windowDuration: TimeInterval = 5.0
        
        for (otherType, scores) in recentCandidateScores where otherType != soundType {
            let recentScores = scores.filter { now.timeIntervalSince($0.time) < windowDuration }
            guard !recentScores.isEmpty else { continue }
            
            // If I dominate this competitor, skip it — it can never suppress me
            if soundType.dominatesOver.contains(otherType) {
                continue
            }
            
            // If the competitor dominates ME, I'm the false positive — suppress me
            if otherType.dominatesOver.contains(soundType) {
                #if DEBUG
                print("[\(elapsed)] ⚠️ \(soundType) SUPPRESSED — \(otherType) dominates (confusion pair) and is also present")
                #endif
                consecutiveDetectionCounts[soundType] = 0
                return
            }
            
            // For non-dominance pairs, fall back to confidence comparison
            let myScores = recentCandidateScores[soundType]?.filter { now.timeIntervalSince($0.time) < windowDuration } ?? []
            let myAvg = myScores.isEmpty ? confidence : myScores.map(\.confidence).reduce(0, +) / Double(myScores.count)
            let otherAvg = recentScores.map(\.confidence).reduce(0, +) / Double(recentScores.count)
            if otherAvg > myAvg {
                #if DEBUG
                print("[\(elapsed)] ⚠️ \(soundType) SUPPRESSED — \(otherType) has higher avg conf (\(String(format: "%.3f", otherAvg)) vs \(String(format: "%.3f", myAvg)))")
                #endif
                consecutiveDetectionCounts[soundType] = 0
                return
            }
        }
        
        // All checks passed - confirm the detection!
        let smoothedConfidence = (confidenceHistory[soundType]?.reduce(0, +) ?? confidence) / Double(max(confidenceHistory[soundType]?.count ?? 1, 1))
        
        #if DEBUG
        print("[\(elapsed)] 🎉 \(soundType) CONFIRMED! smoothedConf=\(String(format: "%.3f", smoothedConfidence)) — triggering notification + haptic + live activity")
        #endif
        
        // Clear all candidate scores on confirmation
        recentCandidateScores.removeAll()
        
        confirmDetection(soundType: soundType, confidence: smoothedConfidence)
    }
    
    /// Handles a confirmed sound detection
    /// - Parameters:
    ///   - soundType: The confirmed sound type
    ///   - confidence: The confidence value
    private func confirmDetection(soundType: DetectedSoundType, confidence: Double) {
        let now = Date()
        
        // Update BOTH per-type and global cooldown timestamps
        lastDetectionTimes[soundType] = now
        lastGlobalDetectionTime = now
        lastConfirmedSoundType = soundType
        
        // Reset consecutive count + confidence history for ALL types
        // This prevents other sound types from firing right after
        consecutiveDetectionCounts.removeAll()
        confidenceHistory.removeAll()
        
        #if DEBUG
        print("[\(elapsed)] 📋 confirmDetection: \(soundType) | globalCooldown set | all counters reset")
        #endif
        
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
        #if DEBUG
        print("[\(elapsed)] 🔔 handleConfirmedDetection: \(event.soundType) conf=\(String(format: "%.3f", event.confidence))")
        print("[\(elapsed)] 🔔   → Triggering haptic...")
        #endif
        HapticManager.shared.playPattern(for: mapToHapticType(event.soundType))
        
        #if DEBUG
        print("[\(elapsed)] 🔔   → Starting/updating Live Activity...")
        #endif
        startOrUpdateLiveActivity(for: event)
        
        #if DEBUG
        print("[\(elapsed)] 🔔   → Posting local notification...")
        #endif
        NotificationManager.shared.postDetectionNotification(for: event)
        
        #if DEBUG
        print("[\(elapsed)] 🔔   → ALL OUTPUTS COMPLETE for \(event.soundType)")
        #endif
    }
    
    private func mapToHapticType(_ soundType: DetectedSoundType) -> HapticSoundType {
        switch soundType {
        case .doorbell: return .doorbell
        case .siren: return .siren
        case .knock: return .knock
        case .alarm: return .alarm
        case .smokeAlarm: return .smokeAlarm
        case .dogBark: return .dogBark
        case .babyCry: return .babyCry
        case .catMeow: return .catMeow
        case .waterRunning: return .waterRunning
        case .speech: return .speech
        case .phoneRinging: return .phoneRinging
        case .carHorn: return .carHorn
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
        let requiredFrames = type.requiredFrames
        
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
        guard let classificationResult = result as? SNClassificationResult else {
            return
        }
        
        // Collect ALL above-threshold candidates and find the best match
        var bestMatch: (soundType: DetectedSoundType, confidence: Double)?
        var allCandidates: [(soundType: DetectedSoundType, confidence: Double)] = []
        
        for classification in classificationResult.classifications {
            let identifier = classification.identifier
            let confidence = Double(classification.confidence)
            
            if let soundType = DetectedSoundType(classifierLabel: identifier) {
                // Track ALL above-threshold candidates for false positive suppression
                if confidence >= soundType.confidenceThreshold {
                    allCandidates.append((soundType, confidence))
                }
                if bestMatch == nil || confidence > bestMatch!.confidence {
                    bestMatch = (soundType, confidence)
                }
            }
        }
        
        // Process the single best match, but also track all candidates
        if let match = bestMatch {
            Task { @MainActor in
                // Record all above-threshold candidates for competing detection analysis
                let now = Date()
                for candidate in allCandidates {
                    var scores = self.recentCandidateScores[candidate.soundType] ?? []
                    scores.append((time: now, confidence: candidate.confidence))
                    // Keep only last 5 seconds of scores
                    scores = scores.filter { now.timeIntervalSince($0.time) < 5.0 }
                    self.recentCandidateScores[candidate.soundType] = scores
                }
                
                self.processDetection(
                    soundType: match.soundType,
                    confidence: match.confidence
                )
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
