//
//  HactileLiveActivityManager.swift
//  Hactile
//
//  Centralized Live Activity lifecycle manager.
//
//  ## Design Philosophy
//  This manager owns and controls exactly ONE Live Activity at a time.
//  All ActivityKit interactions are abstracted here to keep the UI layer
//  and audio processing layer clean and focused on their responsibilities.
//
//  ## Why Centralized Ownership?
//  1. iOS limits apps to a small number of concurrent Live Activities
//  2. Multiple activities for the same purpose confuse users
//  3. Centralized control makes state easier to reason about
//  4. Prevents race conditions when rapid detections occur
//
//  ## Thread Safety
//  All public methods dispatch to MainActor to ensure thread-safe
//  access to the activity reference and ActivityKit APIs.
//

import Foundation
import ActivityKit
import SwiftUI
import Combine

// MARK: - Type Import Note
// DetectedSoundType and HactileAttributes are defined in SharedTypes.swift
// This file uses those shared definitions directly - no bridge needed

// MARK: - Live Activity Manager

/// Manages the lifecycle of Hactile's Live Activity (Dynamic Island).
///
/// ## Responsibilities
/// - Start a Live Activity when a sound is first detected
/// - Update the existing activity when subsequent sounds are detected
/// - End the activity when listening stops
/// - Handle ActivityKit authorization and availability gracefully
///
/// ## Usage
/// ```swift
/// // Start or update activity
/// HactileLiveActivityManager.shared.startActivity(
///     detectedSound: .doorbell,
///     confidence: 0.95
/// )
///
/// // End activity
/// HactileLiveActivityManager.shared.endActivity()
/// ```
///
@MainActor
final class HactileLiveActivityManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = HactileLiveActivityManager()
    
    // MARK: - Published State
    
    /// Whether a Live Activity is currently running
    @Published private(set) var isActivityActive: Bool = false
    
    /// The current sound type being displayed (if any)
    @Published private(set) var currentSoundType: DetectedSoundType?
    
    // MARK: - Private Properties
    
    /// The single Live Activity instance owned by this manager
    /// We maintain at most ONE activity at any time
    private var currentActivity: Activity<HactileAttributes>?
    
    /// Location string for the activity (could be enhanced with room detection)
    private var detectionLocation: String? = nil
    
    /// Timestamp of the last activity update.
    /// Used for conservative auto-expiry — if no update for 10 minutes, activity is ended.
    private var lastActivityUpdate: Date?
    
    /// Maximum time (in seconds) an activity can remain without updates before auto-expiry.
    /// Set to 10 minutes to be conservative and avoid aggressive dismissals.
    private let activityExpiryDuration: TimeInterval = 60 * 10
    
    /// Duration (in seconds) a detection alert stays visible before returning to monitoring.
    private let detectionDisplayDuration: TimeInterval = 30.0
    
    /// Task that auto-dismisses the detection alert after `detectionDisplayDuration`.
    private var detectionDismissTask: Task<Void, Never>?
    
    /// Whether the current activity is in monitoring mode (vs detection mode).
    private var isMonitoringActivity: Bool = false
    
    // MARK: - Initialization
    
    private init() {
        // Check for any existing activities from a previous session
        // and clean them up to ensure a fresh state
        cleanupStaleActivities()
    }
    
    // MARK: - Availability Check
    
    /// Checks if Live Activities are available on this device/OS version
    ///
    /// Live Activities require:
    /// - iOS 16.1+
    /// - User authorization
    /// - Device support (not available on all devices)
    private var areActivitiesAvailable: Bool {
        guard #available(iOS 16.1, *) else {
            #if DEBUG
            print("LiveActivityManager: iOS 16.1+ required for Live Activities")
            #endif
            return false
        }
        
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }
    
    // MARK: - Public API
    
    /// Starts a new Live Activity or updates the existing one
    ///
    /// This method implements "smart" activity management:
    /// - If no activity exists → create one
    /// - If an activity exists → update it with the new sound
    ///
    /// This ensures we never have multiple activities running simultaneously.
    ///
    /// - Parameters:
    ///   - detectedSound: The type of sound that was detected
    ///   - confidence: Detection confidence (0.0 - 1.0), defaults to 0.95
    ///   - location: Optional location string (e.g., "Living Room")
    func startActivity(
        detectedSound: DetectedSoundType,
        confidence: Double = 0.95,
        location: String? = nil
    ) {
        guard areActivitiesAvailable else {
            #if DEBUG
            print("LiveActivityManager: Activities not available, skipping")
            #endif
            return
        }
        
        // Store location for potential updates
        if let location = location {
            detectionLocation = location
        }
        
        // If we have a monitoring activity, ALWAYS end it and create a fresh detection activity.
        // Attributes (soundType, location) are immutable after creation,
        // so we can't update a monitoring activity into a detection activity.
        if currentActivity != nil && isMonitoringActivity {
            Task {
                await endActivityAsync()
                createNewActivity(
                    soundType: detectedSound,
                    confidence: confidence,
                    location: detectionLocation
                )
                scheduleDetectionDismiss()
            }
            return
        }
        
        // If we have an existing detection activity
        if currentActivity != nil {
            // Check for auto-expiry before updating
            if hasActivityExpired() {
                Task {
                    await endActivityAsync()
                    createNewActivity(
                        soundType: detectedSound,
                        confidence: confidence,
                        location: detectionLocation
                    )
                    scheduleDetectionDismiss()
                }
                return
            }
            
            // Update the existing detection activity
            // If sound type changed, end and recreate (attributes are immutable)
            updateActivity(confidence: confidence, detectedSound: detectedSound)
            scheduleDetectionDismiss() // Reset the 30s timer
            return
        }
        
        // Create a new detection activity
        createNewActivity(
            soundType: detectedSound,
            confidence: confidence,
            location: detectionLocation
        )
        scheduleDetectionDismiss()
    }
    
    /// Updates the existing Live Activity with new detection data
    ///
    /// Call this when:
    /// - A new sound is detected while an activity is running
    /// - Confidence level changes significantly
    /// - The detected sound type changes
    ///
    /// - Parameters:
    ///   - confidence: Updated confidence value
    ///   - detectedSound: The newly detected sound type
    func updateActivity(confidence: Double, detectedSound: DetectedSoundType) {
        guard areActivitiesAvailable else { return }
        guard let activity = currentActivity else {
            // No activity to update - start a new one instead
            startActivity(detectedSound: detectedSound, confidence: confidence)
            return
        }
        
        // Create updated content state
        let updatedState = HactileAttributes.ContentState(
            confidence: confidence,
            detectionTimestamp: Date(),
            isAcknowledged: false
        )
        
        // Update the activity asynchronously
        Task {
            // Check if the sound type changed - if so, we need to end and restart
            // because attributes (including soundType) are immutable after creation
            if currentSoundType != detectedSound {
                await endActivityAsync()
                createNewActivity(
                    soundType: detectedSound,
                    confidence: confidence,
                    location: detectionLocation
                )
                return
            }
            
            // Update with new state
            let content = ActivityContent(state: updatedState, staleDate: nil)
            await activity.update(content)
            
            // Refresh the update timestamp to prevent expiry
            await MainActor.run {
                self.lastActivityUpdate = Date()
            }
            
            #if DEBUG
            print("LiveActivityManager: Updated activity - \(detectedSound), confidence: \(confidence)")
            #endif
        }
    }
    
    /// Marks the current activity as acknowledged
    ///
    /// Called when the user taps to acknowledge a detection.
    /// Switches from detection mode to monitoring mode if still listening.
    func acknowledgeActivity() {
        guard let activity = currentActivity else { return }
        
        #if DEBUG
        print("LiveActivityManager: User acknowledged detection")
        #endif
        
        // If listening is still active, switch to monitoring mode
        if SoundRecognitionManager.shared.isListening {
            let monitoringState = HactileAttributes.ContentState(
                confidence: 0.0, // 0 = monitoring mode
                detectionTimestamp: Date(),
                isAcknowledged: false
            )
            
            Task {
                let content = ActivityContent(
                    state: monitoringState,
                    staleDate: Date().addingTimeInterval(60 * 60)
                )
                await activity.update(content)
                
                #if DEBUG
                print("LiveActivityManager: Switched to monitoring mode after acknowledge")
                #endif
            }
        } else {
            // Not listening anymore - just end the activity
            endActivity()
        }
    }
    
    /// Ends the current Live Activity immediately
    ///
    /// Call this when:
    /// - The user stops listening
    /// - The app is terminated
    /// - A timeout period has elapsed
    func endActivity() {
        guard areActivitiesAvailable else { return }
        Task {
            await endActivityAsync()
        }
    }
    
    /// Async version of endActivity for internal use
    private func endActivityAsync() async {
        guard let activity = currentActivity else { return }
        
        // Cancel any pending dismiss task
        detectionDismissTask?.cancel()
        detectionDismissTask = nil
        
        // Create final state for dismissal
        let finalState = HactileAttributes.ContentState(
            confidence: 0,
            detectionTimestamp: Date(),
            isAcknowledged: true
        )
        
        // End the activity with immediate dismissal
        let content = ActivityContent(state: finalState, staleDate: nil)
        await activity.end(content, dismissalPolicy: .immediate)
        
        // Clear our reference
        currentActivity = nil
        currentSoundType = nil
        isActivityActive = false
        lastActivityUpdate = nil
        isMonitoringActivity = false
        
        #if DEBUG
        print("LiveActivityManager: Activity ended")
        #endif
    }
    
    // MARK: - Expiry Check
    
    /// Checks if the current activity has expired due to inactivity.
    /// Returns true if no update has occurred for `activityExpiryDuration` (10 minutes).
    /// This is a conservative check — we only expire on the next interaction, not via timers.
    private func hasActivityExpired() -> Bool {
        guard let lastUpdate = lastActivityUpdate else {
            // No timestamp means activity was never properly started
            return true
        }
        
        let elapsed = Date().timeIntervalSince(lastUpdate)
        return elapsed >= activityExpiryDuration
    }
    
    // MARK: - Private Methods
    
    /// Creates a new Live Activity
    ///
    /// - Parameters:
    ///   - soundType: The detected sound type
    ///   - confidence: Detection confidence
    ///   - location: Optional location string
    private func createNewActivity(
        soundType: DetectedSoundType,
        confidence: Double,
        location: String?
    ) {
        // Create attributes (static data for the activity)
        let attributes = HactileAttributes(
            soundType: soundType,
            location: location
        )
        
        // Create initial content state (dynamic data)
        let initialState = HactileAttributes.ContentState(
            confidence: confidence,
            detectionTimestamp: Date(),
            isAcknowledged: false
        )
        
        // Configure activity content
        let content = ActivityContent(
            state: initialState,
            staleDate: Date().addingTimeInterval(60 * 5) // Stale after 5 minutes
        )
        
        do {
            // Request a new activity
            let activity = try Activity<HactileAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil // No push updates - we're offline-only
            )
            
            // Store reference
            currentActivity = activity
            currentSoundType = soundType
            isActivityActive = true
            lastActivityUpdate = Date()
            isMonitoringActivity = false // This is a detection activity
            
            #if DEBUG
            print("LiveActivityManager: Created detection activity for \(soundType)")
            #endif
            
        } catch {
            #if DEBUG
            print("LiveActivityManager: Failed to create activity: \(error.localizedDescription)")
            #endif
            
            // Fail silently - the app continues to work without Live Activities
            currentActivity = nil
            currentSoundType = nil
            isActivityActive = false
        }
    }
    
    /// Schedules auto-dismiss of the detection alert after `detectionDisplayDuration`.
    /// After the timeout, the activity transitions back to monitoring mode.
    private func scheduleDetectionDismiss() {
        // Cancel any existing dismiss task
        detectionDismissTask?.cancel()
        
        detectionDismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(30.0 * 1_000_000_000))
            } catch {
                // Task was cancelled (new detection or manual dismiss)
                return
            }
            
            guard let self = self else { return }
            guard !Task.isCancelled else { return }
            
            // Only transition to monitoring if we're still listening
            if SoundRecognitionManager.shared.isListening {
                #if DEBUG
                print("LiveActivityManager: Detection auto-dismissed after 30s, returning to monitoring")
                #endif
                
                // End detection activity and create monitoring activity
                await self.endActivityAsync()
                self.createMonitoringActivity()
            } else {
                // Not listening, just end the activity
                await self.endActivityAsync()
            }
        }
    }
    
    /// Cleans up any stale activities from previous app sessions
    ///
    /// This handles the case where the app was terminated while
    /// an activity was running. We end all existing activities
    /// to start fresh.
    private func cleanupStaleActivities() {
        guard areActivitiesAvailable else { return }
        Task {
            for activity in Activity<HactileAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            
            #if DEBUG
            if !Activity<HactileAttributes>.activities.isEmpty {
                print("LiveActivityManager: Cleaned up stale activities")
            }
            #endif
        }
    }
}

// MARK: - App Lifecycle Integration

extension HactileLiveActivityManager {
    
    /// Called when the app is about to terminate
    /// Ensures activities are properly cleaned up
    func appWillTerminate() {
        // End any active activity synchronously if possible
        if let activity = currentActivity {
            let finalState = HactileAttributes.ContentState(
                confidence: 0,
                detectionTimestamp: Date(),
                isAcknowledged: true
            )
            
            Task {
                let content = ActivityContent(state: finalState, staleDate: nil)
                await activity.end(content, dismissalPolicy: .immediate)
            }
        }
    }
    
    /// Called when the app enters background
    /// Live Activities continue to run in background, but we may want
    /// to update their content to reflect background state
    func appDidEnterBackground() {
        #if DEBUG
        print("LiveActivityManager: App entered background, activity continues")
        #endif
        
        // DON'T switch to monitoring mode if we recently showed a detection
        // Let the user see the detection for at least 30 seconds
        if let lastUpdate = lastActivityUpdate {
            let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
            if timeSinceLastUpdate < 30.0 {
                #if DEBUG
                print("LiveActivityManager: Recent detection shown, keeping it visible (waited \(Int(timeSinceLastUpdate))s)")
                #endif
                return
            }
        }
        
        // Only switch to monitoring if no recent detection
        if currentActivity != nil && SoundRecognitionManager.shared.isListening {
            #if DEBUG
            print("LiveActivityManager: Switching to monitoring mode after 30s")
            #endif
            startMonitoringActivity()
        }
    }
    
    /// Starts a monitoring Live Activity to show listening state
    /// Can be called from foreground or background
    /// This shows the user that Hactile is actively listening
    func startMonitoringActivity() {
        guard areActivitiesAvailable else {
            #if DEBUG
            print("LiveActivityManager: Activities not available")
            #endif
            return
        }
        
        // Only create if listening is active
        guard SoundRecognitionManager.shared.isListening else {
            #if DEBUG
            print("LiveActivityManager: Not listening, skipping monitoring activity")
            #endif
            return
        }
        
        // If there's already an activity, check if it's a detection activity
        if let existingActivity = currentActivity {
            // Check if this is a detection activity (confidence > 0)
            // If so, NEVER override it automatically - only user acknowledge should do that
            if let lastUpdate = lastActivityUpdate {
                let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
                
                // Don't override recent detections (at least 30 seconds)
                if timeSinceLastUpdate < 30.0 {
                    #if DEBUG
                    print("LiveActivityManager: Skipping monitoring update - detection still visible (\(Int(timeSinceLastUpdate))s ago)")
                    #endif
                    return
                }
            }
            
            // Additional check: If current sound type is set (detection mode), don't override
            // This prevents monitoring from overriding when user is viewing the detection
            if currentSoundType != nil {
                #if DEBUG
                print("LiveActivityManager: Skipping monitoring update - detection is active")
                #endif
                return
            }
            
            #if DEBUG
            print("LiveActivityManager: Updating existing activity to monitoring mode")
            #endif
            
            let monitoringState = HactileAttributes.ContentState(
                confidence: 0.0, // 0 = monitoring mode
                detectionTimestamp: Date(),
                isAcknowledged: false
            )
            
            Task {
                let content = ActivityContent(
                    state: monitoringState,
                    staleDate: Date().addingTimeInterval(60 * 60)
                )
                await existingActivity.update(content)
                // Don't update lastActivityUpdate here - keep the detection timestamp
            }
            return
        }
        
        // Create new monitoring activity
        createMonitoringActivity()
    }
    
    /// Legacy method - now calls startMonitoringActivity()
    /// Starts a monitoring Live Activity when app enters background
    /// This shows the user that Hactile is actively listening
    func startBackgroundMonitoringActivity() {
        guard areActivitiesAvailable else {
            #if DEBUG
            print("LiveActivityManager: Activities not available")
            #endif
            return
        }
        
        // Only create if listening is active
        guard SoundRecognitionManager.shared.isListening else {
            #if DEBUG
            print("LiveActivityManager: Not listening, skipping monitoring activity")
            #endif
            return
        }
        
        // If there's already an activity, update it to monitoring mode instead of skipping
        if let existingActivity = currentActivity {
            #if DEBUG
            print("LiveActivityManager: Updating existing activity to monitoring mode")
            #endif
            
            let monitoringState = HactileAttributes.ContentState(
                confidence: 0.0, // 0 = monitoring mode
                detectionTimestamp: Date(),
                isAcknowledged: false
            )
            
            Task {
                let content = ActivityContent(
                    state: monitoringState,
                    staleDate: Date().addingTimeInterval(60 * 60)
                )
                await existingActivity.update(content)
                lastActivityUpdate = Date()
            }
            return
        }
        
        // Just call the new method
        startMonitoringActivity()
    }
    
    /// Creates a new monitoring activity
    private func createMonitoringActivity() {
        // Create a "monitoring" activity to show app is active
        // Use a generic sound type to indicate listening state
        let attributes = HactileAttributes(
            soundType: .doorbell, // Placeholder - will update on actual detection
            location: "Monitoring"
        )
        
        let initialState = HactileAttributes.ContentState(
            confidence: 0.0, // 0 indicates monitoring, not detecting
            detectionTimestamp: Date(),
            isAcknowledged: false
        )
        
        let content = ActivityContent(
            state: initialState,
            staleDate: Date().addingTimeInterval(60 * 60) // 1 hour stale date
        )
        
        do {
            let activity = try Activity<HactileAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            
            currentActivity = activity
            currentSoundType = .doorbell
            isActivityActive = true
            lastActivityUpdate = Date()
            isMonitoringActivity = true // Flag this as a monitoring activity
            
            #if DEBUG
            print("LiveActivityManager: Started monitoring activity - Dynamic Island should appear!")
            #endif
            
        } catch {
            #if DEBUG
            print("LiveActivityManager: Failed to create monitoring activity: \(error.localizedDescription)")
            #endif
        }
    }
}
