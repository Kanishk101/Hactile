//
//  HapticManager.swift
//  Hactile
//
//  Centralized haptic feedback manager that converts detected sounds into
//  distinct physical sensations using Core Haptics and system fallbacks.
//
//  ## Design Philosophy
//  Each sound type has a unique "tactile signature" that helps users identify
//  what was detected without looking at their device. This is especially important
//  for accessibility and situations where visual attention isn't possible.
//
//  ## iOS Background Execution Constraints
//  Core Haptics (CHHapticEngine) is designed for foreground use only.
//  When the app is backgrounded, iOS suspends the haptic engine and may
//  terminate it entirely. Attempting to play patterns in the background
//  will fail silently or cause errors.
//
//  Therefore, this manager implements a dual-mode system:
//  - **Foreground**: Rich Core Haptics patterns with textures and curves
//  - **Background**: Simple UIKit feedback generators (system-guaranteed)
//

import Foundation
import CoreHaptics
import UIKit
import AudioToolbox

// MARK: - Detected Sound Type (Local Reference)

/// Sound types that can trigger haptic feedback
/// Mirrors the DetectedSoundType enum from SoundRecognitionManager
enum HapticSoundType: String, CaseIterable {
    case doorbell
    case siren
    case knock
    case alarm
    case dogBark
    case babyCry
    case carHorn
    case glassBreak
    case gunshot
    case catMeow
    case waterRunning
    case speech
    case applause
    case cough
    case whistle
}

// MARK: - Haptic Manager

/// Centralized manager for all haptic feedback in Hactile.
///
/// ## Responsibilities
/// - Translates detected sounds into appropriate haptic patterns
/// - Manages Core Haptics engine lifecycle
/// - Falls back to system haptics when Core Haptics is unavailable
/// - Handles engine interruptions and restarts gracefully
///
/// ## Usage
/// ```swift
/// HapticManager.shared.playPattern(for: .doorbell)
/// ```
///
final class HapticManager {
    
    // MARK: - Singleton
    
    static let shared = HapticManager()
    
    // MARK: - Properties
    
    /// The Core Haptics engine instance
    /// Lazily initialized when first needed
    private var engine: CHHapticEngine?
    
    /// Whether the device supports haptics
    /// Checked once at initialization for performance
    private let supportsHaptics: Bool
    
    /// Whether the engine is currently running
    private var engineIsRunning: Bool = false
    
    /// Queue for thread-safe engine operations
    private let hapticQueue = DispatchQueue(label: "com.hactile.haptics", qos: .userInteractive)
    
    // MARK: - System Feedback Generators
    
    /// Pre-initialized feedback generators for quick response
    /// These are used as fallbacks when Core Haptics isn't available
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let impactHeavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let impactMediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let impactLightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let impactRigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    
    // MARK: - Initialization
    
    private init() {
        // Check hardware capabilities once
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        
        // Prepare system generators (they need time to spin up)
        prepareSystemGenerators()
        
        // Set up Core Haptics if supported
        if supportsHaptics {
            setupEngine()
        }
        
        #if DEBUG
        print("HapticManager initialized. Haptics supported: \(supportsHaptics)")
        #endif
    }
    
    // MARK: - System Generators Setup
    
    /// Prepares all system feedback generators
    /// This reduces latency when haptics are triggered
    private func prepareSystemGenerators() {
        notificationGenerator.prepare()
        impactHeavyGenerator.prepare()
        impactMediumGenerator.prepare()
        impactLightGenerator.prepare()
        impactRigidGenerator.prepare()
    }
    
    // MARK: - Engine Setup
    
    /// Creates and configures the Core Haptics engine
    ///
    /// The engine is set up with handlers for:
    /// - **Reset**: Called when the engine needs to be restarted
    /// - **Stopped**: Called when the engine is stopped by the system
    ///
    /// These handlers are critical for graceful recovery from interruptions
    /// like phone calls, Siri activation, or app backgrounding.
    private func setupEngine() {
        guard supportsHaptics else { return }
        
        do {
            engine = try CHHapticEngine()
            
            // Handler called when engine is reset (e.g., after audio session interruption)
            engine?.resetHandler = { [weak self] in
                #if DEBUG
                print("HapticManager: Engine reset requested")
                #endif
                self?.restartEngine()
            }
            
            // Handler called when engine is stopped by the system
            // This happens when:
            // - App goes to background
            // - Audio session is interrupted (phone call, Siri)
            // - System resource constraints
            engine?.stoppedHandler = { [weak self] reason in
                #if DEBUG
                print("HapticManager: Engine stopped. Reason: \(reason.rawValue)")
                #endif
                self?.engineIsRunning = false
            }
            
            #if DEBUG
            print("HapticManager: Engine created successfully")
            #endif
            
        } catch {
            #if DEBUG
            print("HapticManager: Failed to create engine: \(error.localizedDescription)")
            #endif
            engine = nil
        }
    }
    
    /// Starts the haptic engine
    /// Called lazily before playing patterns
    private func startEngine() {
        guard supportsHaptics else { return }
        
        if engine == nil {
            setupEngine()
        }
        
        guard let engine = engine, !engineIsRunning else { return }
        
        do {
            try engine.start()
            engineIsRunning = true
            
            #if DEBUG
            print("HapticManager: Engine started")
            #endif
        } catch {
            #if DEBUG
            print("HapticManager: Failed to start engine: \(error.localizedDescription)")
            #endif
            engineIsRunning = false
        }
    }
    
    /// Restarts the haptic engine after a reset or interruption
    private func restartEngine() {
        hapticQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Stop if running
            self.engine?.stop()
            self.engineIsRunning = false
            
            // Recreate and start
            self.setupEngine()
            self.startEngine()
        }
    }
    
    /// Stops the haptic engine
    /// Called when the app goes to background to save resources
    func stopEngine() {
        guard engineIsRunning else { return }
        engine?.stop()
        engineIsRunning = false
        
        #if DEBUG
        print("HapticManager: Engine stopped manually")
        #endif
    }
    
    // MARK: - Public API
    
    /// Plays the appropriate haptic pattern for a detected sound
    ///
    /// This is the main entry point for triggering haptics.
    /// It automatically routes to Core Haptics (foreground) or
    /// system haptics (background) based on app state.
    ///
    /// - Parameter sound: The type of sound that was detected
    func playPattern(for sound: HapticSoundType) {
        // Determine if we're in foreground
        let isInForeground = isAppInForeground()
        
        if isInForeground && supportsHaptics {
            // Use rich Core Haptics patterns in foreground
            playCoreHapticsPattern(for: sound)
        } else {
            // Fall back to system haptics in background or if Core Haptics unavailable
            playSystemHapticFallback(for: sound)
        }
    }
    
    /// Simple impact feedback for UI interactions
    /// - Parameter style: The impact style to use
    func playImpact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .heavy:
            generator = impactHeavyGenerator
        case .medium:
            generator = impactMediumGenerator
        case .light:
            generator = impactLightGenerator
        case .rigid:
            generator = impactRigidGenerator
        case .soft:
            generator = impactLightGenerator // Use light as soft equivalent
        @unknown default:
            generator = impactMediumGenerator
        }
        
        generator.impactOccurred()
        generator.prepare()
    }
    
    /// Selection feedback for UI state changes
    func playSelection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        generator.prepare()
    }
    
    /// Notification feedback for alerts
    /// - Parameter type: The notification type
    func playNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }
    
    // MARK: - App State Detection
    
    /// Determines if the app is currently in the foreground
    ///
    /// We use UIApplication.shared.applicationState instead of SwiftUI's
    /// scenePhase because this manager operates independently of the view
    /// hierarchy and needs direct access to the application state.
    ///
    /// - Returns: True if the app is active in the foreground
    private func isAppInForeground() -> Bool {
        // Must be called on main thread
        if Thread.isMainThread {
            return UIApplication.shared.applicationState == .active
        } else {
            return DispatchQueue.main.sync {
                UIApplication.shared.applicationState == .active
            }
        }
    }
    
    // MARK: - Core Haptics Pattern Playback
    
    /// Plays a Core Haptics pattern for the given sound type
    /// This should only be called when the app is in foreground
    ///
    /// - Parameter sound: The sound type to create a pattern for
    private func playCoreHapticsPattern(for sound: HapticSoundType) {
        hapticQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Ensure engine is running
            self.startEngine()
            
            guard self.engineIsRunning, let engine = self.engine else {
                // Fall back to system haptics if engine isn't available
                DispatchQueue.main.async {
                    self.playSystemHapticFallback(for: sound)
                }
                return
            }
            
            // Build the pattern for this sound type
            let pattern = self.buildPattern(for: sound)
            
            guard let pattern = pattern else {
                #if DEBUG
                print("HapticManager: Failed to build pattern for \(sound)")
                #endif
                return
            }
            
            do {
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
                
                #if DEBUG
                print("HapticManager: Playing Core Haptics pattern for \(sound)")
                #endif
            } catch {
                #if DEBUG
                print("HapticManager: Failed to play pattern: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    // MARK: - Pattern Builders
    
    /// Builds a CHHapticPattern for the given sound type
    ///
    /// Each pattern is designed to create a unique "tactile signature"
    /// that users can learn to recognize without visual feedback.
    ///
    /// - Parameter sound: The sound type to build a pattern for
    /// - Returns: A CHHapticPattern, or nil if creation fails
    private func buildPattern(for sound: HapticSoundType) -> CHHapticPattern? {
        switch sound {
        case .doorbell:
            return buildDoorbellPattern()
        case .siren, .carHorn:
            return buildSirenPattern()
        case .knock:
            return buildKnockPattern()
        case .alarm, .glassBreak, .gunshot:
            return buildAlarmPattern()
        case .dogBark, .catMeow:
            return buildDogBarkPattern()
        case .babyCry:
            return buildBabyCryPattern()
        case .waterRunning, .speech, .applause, .cough, .whistle:
            return buildKnockPattern() // Gentle alert for ambient sounds
        }
    }
    
    /// 🛎 Doorbell Pattern
    ///
    /// Two sharp, crisp transient events spaced 300ms apart.
    /// Medium intensity with high sharpness.
    /// Feels like: "Ding–Dong"
    private func buildDoorbellPattern() -> CHHapticPattern? {
        do {
            // First "Ding" - sharp, crisp
            let ding = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
                ],
                relativeTime: 0
            )
            
            // Second "Dong" - slightly softer, lower pitch feel
            let dong = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                ],
                relativeTime: 0.3 // 300ms later
            )
            
            return try CHHapticPattern(events: [ding, dong], parameters: [])
        } catch {
            #if DEBUG
            print("HapticManager: Failed to create doorbell pattern: \(error)")
            #endif
            return nil
        }
    }
    
    /// 🚨 Siren Pattern
    ///
    /// Continuous haptic event with intensity that rises and falls,
    /// creating an oscillating wave sensation.
    /// Repeated 3 times with short pauses.
    /// Duration ≈ 1 second per cycle.
    /// Feels like: oscillating emergency wave
    private func buildSirenPattern() -> CHHapticPattern? {
        do {
            var events: [CHHapticEvent] = []
            var parameterCurves: [CHHapticParameterCurve] = []
            
            // Create 3 oscillation cycles
            for cycle in 0..<3 {
                let cycleStart = Double(cycle) * 0.6 // Each cycle is 0.5s + 0.1s pause
                
                // Continuous event for this cycle
                let continuous = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ],
                    relativeTime: cycleStart,
                    duration: 0.5
                )
                events.append(continuous)
                
                // Intensity curve: low → high → low (oscillation)
                let intensityCurve = CHHapticParameterCurve(
                    parameterID: .hapticIntensityControl,
                    controlPoints: [
                        CHHapticParameterCurve.ControlPoint(relativeTime: cycleStart, value: 0.3),
                        CHHapticParameterCurve.ControlPoint(relativeTime: cycleStart + 0.25, value: 1.0),
                        CHHapticParameterCurve.ControlPoint(relativeTime: cycleStart + 0.5, value: 0.3)
                    ],
                    relativeTime: 0
                )
                parameterCurves.append(intensityCurve)
            }
            
            return try CHHapticPattern(events: events, parameterCurves: parameterCurves)
        } catch {
            #if DEBUG
            print("HapticManager: Failed to create siren pattern: \(error)")
            #endif
            return nil
        }
    }
    
    /// 🚪 Knock Pattern
    ///
    /// 3 rapid transients with high sharpness and medium intensity.
    /// Very short spacing (80ms) to simulate knocking rhythm.
    /// Feels like: dry, gritty taps
    private func buildKnockPattern() -> CHHapticPattern? {
        do {
            var events: [CHHapticEvent] = []
            
            // Three rapid knocks
            for i in 0..<3 {
                let knock = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.95) // Very sharp
                    ],
                    relativeTime: Double(i) * 0.08 // 80ms apart
                )
                events.append(knock)
            }
            
            return try CHHapticPattern(events: events, parameters: [])
        } catch {
            #if DEBUG
            print("HapticManager: Failed to create knock pattern: \(error)")
            #endif
            return nil
        }
    }
    
    /// ⏰ Alarm Pattern
    ///
    /// Urgent, attention-grabbing pattern with alternating
    /// high-intensity bursts.
    /// Feels like: urgent pulsing
    private func buildAlarmPattern() -> CHHapticPattern? {
        do {
            var events: [CHHapticEvent] = []
            
            // 4 rapid high-intensity bursts
            for i in 0..<4 {
                // Short continuous burst
                let burst = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                    ],
                    relativeTime: Double(i) * 0.2,
                    duration: 0.1
                )
                events.append(burst)
            }
            
            return try CHHapticPattern(events: events, parameters: [])
        } catch {
            #if DEBUG
            print("HapticManager: Failed to create alarm pattern: \(error)")
            #endif
            return nil
        }
    }
    
    /// 🐕 Dog Bark Pattern
    ///
    /// Irregular, heavy transients with high intensity and low sharpness.
    /// Subtle randomization in timing creates organic feel.
    /// Feels like: heavy thuds
    ///
    /// Note: Timing variations are kept within a small, predictable range
    /// to maintain a consistent feel while adding organic variation.
    private func buildDogBarkPattern() -> CHHapticPattern? {
        do {
            var events: [CHHapticEvent] = []
            
            // Base timings with slight variations
            // Using deterministic "random" values within safe ranges
            let timings: [Double] = [0.0, 0.12, 0.28] // Irregular spacing
            let intensities: [Float] = [0.9, 1.0, 0.85] // Slight variation
            
            for (index, time) in timings.enumerated() {
                let bark = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensities[index]),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3) // Low sharpness = thuddy
                    ],
                    relativeTime: time
                )
                events.append(bark)
            }
            
            return try CHHapticPattern(events: events, parameters: [])
        } catch {
            #if DEBUG
            print("HapticManager: Failed to create dog bark pattern: \(error)")
            #endif
            return nil
        }
    }
    
    /// 👶 Baby Cry Pattern
    ///
    /// Urgent pattern that demands attention.
    /// Combines continuous wave with sharp transients.
    /// Feels like: urgent, attention-demanding pulse
    private func buildBabyCryPattern() -> CHHapticPattern? {
        do {
            var events: [CHHapticEvent] = []
            
            // Underlying continuous "wail"
            let wail = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                ],
                relativeTime: 0,
                duration: 0.8
            )
            events.append(wail)
            
            // Overlaid sharp "cries"
            for i in 0..<3 {
                let cry = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                    ],
                    relativeTime: Double(i) * 0.25 + 0.1
                )
                events.append(cry)
            }
            
            // Intensity curve for the wail (rising urgency)
            let intensityCurve = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 0.4),
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0.4, value: 1.0),
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0.8, value: 0.5)
                ],
                relativeTime: 0
            )
            
            return try CHHapticPattern(events: events, parameterCurves: [intensityCurve])
        } catch {
            #if DEBUG
            print("HapticManager: Failed to create baby cry pattern: \(error)")
            #endif
            return nil
        }
    }
    
    // MARK: - Fallback Logic
    
    /// Plays simplified system haptics as a fallback
    ///
    /// This method is used when:
    /// - The app is in the background (Core Haptics not allowed)
    /// - The device doesn't support Core Haptics
    /// - The haptic engine failed to start
    ///
    /// System haptics (UIFeedbackGenerator) are simpler but guaranteed to work
    /// in more situations than Core Haptics.
    ///
    /// - Parameter sound: The sound type to provide feedback for
    private func playSystemHapticFallback(for sound: HapticSoundType) {
        // Ensure we're on the main thread for UIKit haptics
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.playSystemHapticFallback(for: sound)
            }
            return
        }
        
        #if DEBUG
        print("HapticManager: Using system fallback for \(sound)")
        #endif
        
        switch sound {
        case .doorbell:
            // Success notification for friendly doorbell
            notificationGenerator.notificationOccurred(.success)
            notificationGenerator.prepare()
            
        case .siren, .carHorn:
            // Warning notification for urgent siren/horn
            notificationGenerator.notificationOccurred(.warning)
            notificationGenerator.prepare()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.notificationGenerator.notificationOccurred(.warning)
                self?.notificationGenerator.prepare()
            }
            
        case .knock:
            // Multiple rigid impacts for knock
            impactRigidGenerator.impactOccurred()
            impactRigidGenerator.prepare()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.impactRigidGenerator.impactOccurred()
                self?.impactRigidGenerator.prepare()
            }
            
        case .alarm, .glassBreak, .gunshot:
            // Error notification for urgent alarm/safety sounds
            notificationGenerator.notificationOccurred(.error)
            notificationGenerator.prepare()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.notificationGenerator.notificationOccurred(.error)
                self?.notificationGenerator.prepare()
            }
            
        case .dogBark, .catMeow:
            // Heavy impacts for animal sounds
            impactHeavyGenerator.impactOccurred()
            impactHeavyGenerator.prepare()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.impactHeavyGenerator.impactOccurred()
                self?.impactHeavyGenerator.prepare()
            }
            
        case .babyCry:
            // Error notification for urgent baby cry
            notificationGenerator.notificationOccurred(.error)
            notificationGenerator.prepare()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.impactMediumGenerator.impactOccurred()
                self?.impactMediumGenerator.prepare()
            }
            
        case .waterRunning, .speech, .applause, .cough, .whistle:
            // Light notification for ambient sounds
            impactLightGenerator.impactOccurred()
            impactLightGenerator.prepare()
        }
    }
    
    /// Plays a system vibration using AudioToolbox
    ///
    /// This is the most basic fallback, used when even UIKit haptics
    /// might not be available. Works on all iPhones.
    private func playSystemVibration() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}

// MARK: - App Lifecycle Integration

extension HapticManager {
    
    /// Call when the app enters the foreground
    /// Restarts the haptic engine if needed
    func appDidBecomeActive() {
        if supportsHaptics, !engineIsRunning {
            startEngine()
        }
        prepareSystemGenerators()
        
        #if DEBUG
        print("HapticManager: App became active, engine restarted")
        #endif
    }
    
    /// Call when the app enters the background
    /// Stops the haptic engine to save resources
    func appDidEnterBackground() {
        stopEngine()
        
        #if DEBUG
        print("HapticManager: App entered background, engine stopped")
        #endif
    }
}

// MARK: - Testing Helpers

#if DEBUG
extension HapticManager {
    
    /// Tests all haptic patterns in sequence
    /// Useful for demonstrating the tactile signatures
    func testAllPatterns() {
        let sounds = HapticSoundType.allCases
        var delay: TimeInterval = 0
        
        for sound in sounds {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                print("Testing pattern: \(sound)")
                self?.playPattern(for: sound)
            }
            delay += 2.0 // 2 seconds between each pattern
        }
    }
    
    /// Tests a specific pattern
    func testPattern(_ sound: HapticSoundType) {
        print("Testing pattern: \(sound)")
        playPattern(for: sound)
    }
}
#endif
