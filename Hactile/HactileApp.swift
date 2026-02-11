//
//  HactileApp.swift
//  Hactile
//
//  App entry point that manages onboarding flow and manager lifecycle.
//
//  ## Architecture Notes
//  This file is deliberately minimal. It has two responsibilities:
//  1. Decide whether to show onboarding or the main dashboard
//  2. Inject shared managers into the environment
//
//  All business logic lives in the managers, not here.
//
//  ## Why AppStorage?
//  AppStorage provides automatic persistence to UserDefaults.
//  It's the simplest way to track onboarding completion across launches.
//  No need for Core Data or custom persistence for a single boolean.
//

import SwiftUI

@main
struct HactileApp: App {
    
    // MARK: - Onboarding State
    
    /// Tracks whether the user has completed onboarding
    /// This value is automatically persisted to UserDefaults
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    
    // MARK: - Environment
    
    /// Monitors app lifecycle for manager coordination
    @Environment(\.scenePhase) private var scenePhase
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    // User has completed onboarding — show main dashboard
                    ContentView()
                } else {
                    // First launch — show onboarding flow
                    OnboardingView()
                }
            }
            .onAppear {
                // Register notification categories once on app launch
                NotificationManager.shared.registerCategories()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }
    
    // MARK: - Deep Link Handling
    
    /// Handles deep links from Live Activity actions.
    /// When user taps "Acknowledge" on Dynamic Island or Lock Screen,
    /// the app opens with hactile://acknowledge URL.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "hactile" else { return }
        
        switch url.host {
        case "acknowledge":
            // User tapped Acknowledge on Live Activity
            // End the activity immediately, no haptics, no restart
            Task { @MainActor in
                HactileLiveActivityManager.shared.acknowledgeActivity()
            }
            
            #if DEBUG
            print("HactileApp: Handled acknowledge deep link")
            #endif
            
        default:
            #if DEBUG
            print("HactileApp: Unknown deep link: \(url)")
            #endif
        }
    }
    
    // MARK: - Lifecycle Management
    
    /// Coordinates manager lifecycle with app state changes
    ///
    /// This ensures:
    /// - Haptic engine starts when app becomes active
    /// - Resources are released when app goes to background
    /// - Live Activities are properly maintained
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // App is in foreground — prepare managers
            HapticManager.shared.appDidBecomeActive()
            
            #if DEBUG
            print("HactileApp: App became active")
            #endif
            
        case .inactive:
            // App is transitioning — no action needed
            break
            
        case .background:
            // App is in background — conserve resources
            HapticManager.shared.appDidEnterBackground()
            HactileLiveActivityManager.shared.appDidEnterBackground()
            
            // Start Live Activity when app goes to background if listening
            Task { @MainActor in
                if SoundRecognitionManager.shared.isListening {
                    HactileLiveActivityManager.shared.startBackgroundMonitoringActivity()
                }
            }
            
            #if DEBUG
            print("HactileApp: App entered background")
            #endif
            
        @unknown default:
            break
        }
    }
}

// MARK: - Debug Helpers

#if DEBUG
extension HactileApp {
    /// Resets onboarding state for testing
    /// Call from debugger: UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
    static func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
    }
}
#endif
