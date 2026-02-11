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
//  ## State Machine
//  The Live Activity has two modes:
//  1. MONITORING — confidence = 0.0, shows "Listening..." in Dynamic Island
//  2. DETECTION  — confidence > 0.0, shows "Doorbell Detected" etc.
//
//  Transitions:
//  - App backgrounds & listening → start MONITORING activity
//  - Sound detected → end MONITORING, start DETECTION activity
//  - 30s after detection → end DETECTION, start MONITORING activity
//  - User taps Acknowledge → end DETECTION, start MONITORING activity
//  - Listening stops → end any activity
//
//  ## Thread Safety
//  All public methods are on MainActor.
//

import Foundation
import ActivityKit
import SwiftUI
import Combine

// MARK: - Live Activity Manager

@MainActor
final class HactileLiveActivityManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = HactileLiveActivityManager()
    
    // MARK: - Published State
    
    @Published private(set) var isActivityActive: Bool = false
    @Published private(set) var currentSoundType: DetectedSoundType?
    
    // MARK: - Private Properties
    
    /// The single Live Activity instance
    private var currentActivity: Activity<HactileAttributes>?
    
    /// Whether current activity is in monitoring mode
    private var isMonitoringActivity: Bool = false
    
    /// Task that auto-dismisses detection after 30s
    private var detectionDismissTask: Task<Void, Never>?
    
    /// Duration a detection alert stays visible
    private let detectionDisplayDuration: TimeInterval = 30.0
    
    // MARK: - Initialization
    
    private init() {
        cleanupStaleActivities()
    }
    
    // MARK: - Availability
    
    private var areActivitiesAvailable: Bool {
        guard #available(iOS 16.1, *) else { return false }
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }
    
    // MARK: - Public API
    
    /// Called when a sound is detected.
    /// Ends any monitoring activity, creates a detection activity, starts 30s timer.
    func startActivity(
        detectedSound: DetectedSoundType,
        confidence: Double = 0.95,
        location: String? = nil
    ) {
        guard areActivitiesAvailable else {
            #if DEBUG
            print("LiveActivityManager: Activities not available")
            #endif
            return
        }
        
        // Cancel any existing dismiss task
        detectionDismissTask?.cancel()
        detectionDismissTask = nil
        
        // If same sound type is already showing, just update confidence
        if let activity = currentActivity, !isMonitoringActivity, currentSoundType == detectedSound {
            updateExistingActivity(activity, confidence: confidence)
            scheduleDetectionDismiss()
            return
        }
        
        // Otherwise, end whatever is running and create a fresh detection activity
        Task {
            await endActivityImmediately()
            createDetectionActivity(
                soundType: detectedSound,
                confidence: confidence,
                location: location
            )
            scheduleDetectionDismiss()
        }
    }
    
    /// Called when user taps Acknowledge on the Live Activity.
    /// Ends the detection activity, returns to monitoring if still listening.
    func acknowledgeActivity() {
        #if DEBUG
        print("LiveActivityManager: User acknowledged detection")
        #endif
        
        detectionDismissTask?.cancel()
        detectionDismissTask = nil
        
        Task {
            await endActivityImmediately()
            
            // Return to monitoring if still listening
            if SoundRecognitionManager.shared.isListening {
                createMonitoringActivity()
            }
        }
    }
    
    /// Ends the current Live Activity completely.
    func endActivity() {
        detectionDismissTask?.cancel()
        detectionDismissTask = nil
        
        Task {
            await endActivityImmediately()
        }
    }
    
    /// Starts a monitoring activity when app goes to background.
    /// Only if currently listening and no detection is showing.
    func startBackgroundMonitoringActivity() {
        guard areActivitiesAvailable else { return }
        guard SoundRecognitionManager.shared.isListening else { return }
        
        // If there's already an activity, don't create another
        if currentActivity != nil {
            // If it's a detection activity, don't override it
            if !isMonitoringActivity {
                #if DEBUG
                print("LiveActivityManager: Detection active, not overriding with monitoring")
                #endif
                return
            }
            // Already monitoring, nothing to do
            return
        }
        
        createMonitoringActivity()
    }
    
    /// Alias for startBackgroundMonitoringActivity
    func startMonitoringActivity() {
        startBackgroundMonitoringActivity()
    }
    
    func appDidEnterBackground() {
        #if DEBUG
        print("LiveActivityManager: App entered background, activity continues")
        #endif
        // Don't interfere with active detection activities
    }
    
    func appWillTerminate() {
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
    
    // MARK: - Private: Activity Creation
    
    /// Creates a detection activity (sound was detected)
    private func createDetectionActivity(
        soundType: DetectedSoundType,
        confidence: Double,
        location: String?
    ) {
        let attributes = HactileAttributes(
            soundType: soundType,
            location: location
        )
        
        let state = HactileAttributes.ContentState(
            confidence: confidence,
            detectionTimestamp: Date(),
            isAcknowledged: false
        )
        
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(60 * 5)
        )
        
        do {
            let activity = try Activity<HactileAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            
            currentActivity = activity
            currentSoundType = soundType
            isActivityActive = true
            isMonitoringActivity = false
            
            #if DEBUG
            print("LiveActivityManager: ✅ Created DETECTION activity for \(soundType.displayName)")
            #endif
        } catch {
            #if DEBUG
            print("LiveActivityManager: ❌ Failed to create detection activity: \(error.localizedDescription)")
            #endif
            clearState()
        }
    }
    
    /// Creates a monitoring activity (listening, no detection yet)
    private func createMonitoringActivity() {
        guard areActivitiesAvailable else { return }
        guard SoundRecognitionManager.shared.isListening else { return }
        
        let attributes = HactileAttributes(
            soundType: .doorbell, // Placeholder — UI checks confidence=0 to show monitoring mode
            location: "Monitoring"
        )
        
        let state = HactileAttributes.ContentState(
            confidence: 0.0, // 0.0 = monitoring mode
            detectionTimestamp: Date(),
            isAcknowledged: false
        )
        
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(60 * 60)
        )
        
        do {
            let activity = try Activity<HactileAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            
            currentActivity = activity
            currentSoundType = nil
            isActivityActive = true
            isMonitoringActivity = true
            
            #if DEBUG
            print("LiveActivityManager: ✅ Created MONITORING activity")
            #endif
        } catch {
            #if DEBUG
            print("LiveActivityManager: ❌ Failed to create monitoring activity: \(error.localizedDescription)")
            #endif
            clearState()
        }
    }
    
    // MARK: - Private: Updates
    
    /// Updates an existing detection activity with new confidence
    private func updateExistingActivity(_ activity: Activity<HactileAttributes>, confidence: Double) {
        let updatedState = HactileAttributes.ContentState(
            confidence: confidence,
            detectionTimestamp: Date(),
            isAcknowledged: false
        )
        
        Task {
            let content = ActivityContent(state: updatedState, staleDate: nil)
            await activity.update(content)
            
            #if DEBUG
            print("LiveActivityManager: Updated detection confidence to \(Int(confidence * 100))%")
            #endif
        }
    }
    
    // MARK: - Private: Teardown
    
    /// Ends the current activity immediately (async)
    private func endActivityImmediately() async {
        guard let activity = currentActivity else { return }
        
        let finalState = HactileAttributes.ContentState(
            confidence: 0,
            detectionTimestamp: Date(),
            isAcknowledged: true
        )
        
        let content = ActivityContent(state: finalState, staleDate: nil)
        await activity.end(content, dismissalPolicy: .immediate)
        
        clearState()
        
        #if DEBUG
        print("LiveActivityManager: Activity ended")
        #endif
    }
    
    /// Clears all state references
    private func clearState() {
        currentActivity = nil
        currentSoundType = nil
        isActivityActive = false
        isMonitoringActivity = false
    }
    
    // MARK: - Private: Auto-Dismiss Timer
    
    /// After 30s, end detection and return to monitoring
    private func scheduleDetectionDismiss() {
        detectionDismissTask?.cancel()
        
        detectionDismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(30.0 * 1_000_000_000))
            } catch {
                return // Cancelled
            }
            
            guard let self = self, !Task.isCancelled else { return }
            
            #if DEBUG
            print("LiveActivityManager: 30s elapsed, returning to monitoring")
            #endif
            
            await self.endActivityImmediately()
            
            if SoundRecognitionManager.shared.isListening {
                self.createMonitoringActivity()
            }
        }
    }
    
    // MARK: - Cleanup
    
    /// Ends ALL Live Activities immediately and synchronously.
    /// Called during app termination when async operations can't be awaited.
    func endAllActivitiesSync() {
        guard areActivitiesAvailable else { return }
        
        // Cancel any pending dismiss
        detectionDismissTask?.cancel()
        detectionDismissTask = nil
        
        // End our tracked activity
        currentActivity = nil
        currentSoundType = nil
        isMonitoringActivity = false
        
        // End ALL activities from this app
        let finalState = HactileAttributes.ContentState(
            confidence: 0.0,
            detectionTimestamp: Date(),
            isAcknowledged: true
        )
        let finalContent = ActivityContent(state: finalState, staleDate: nil)
        
        Task {
            for activity in Activity<HactileAttributes>.activities {
                await activity.end(finalContent, dismissalPolicy: .immediate)
            }
        }
        
        #if DEBUG
        print("LiveActivityManager: All activities ended (app terminating)")
        #endif
    }
    
    /// Ends all stale activities from previous sessions
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
