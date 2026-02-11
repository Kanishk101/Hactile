//
//  NotificationManager.swift
//  Hactile
//
//  Background notification delivery for confirmed detections.
//  Includes actionable notifications for acknowledging detections.
//

import Foundation
import UserNotifications

// MARK: - Notification Identifiers

enum NotificationIdentifiers {
    static let detectionCategory = "HACTILE_DETECTION"
    static let acknowledgeAction = "ACKNOWLEDGE"
}

// MARK: - Notification Manager

final class NotificationManager: NSObject {
    static let shared = NotificationManager()
    
    /// Tracks whether notification categories have been registered
    private var categoriesRegistered = false
    
    private override init() {
        super.init()
    }
    
    // MARK: - Category Registration
    
    /// Registers notification categories with the system.
    /// Call once on app launch. Safe to call multiple times — only registers once.
    func registerCategories() {
        guard !categoriesRegistered else { return }
        
        // Define the Acknowledge action - handles in background without opening app
        let acknowledgeAction = UNNotificationAction(
            identifier: NotificationIdentifiers.acknowledgeAction,
            title: "Acknowledge",
            options: []  // No options = handles in background without launching app
        )
        
        // Define the detection category with the acknowledge action
        let detectionCategory = UNNotificationCategory(
            identifier: NotificationIdentifiers.detectionCategory,
            actions: [acknowledgeAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Register with the notification center
        UNUserNotificationCenter.current().setNotificationCategories([detectionCategory])
        
        // Set ourselves as delegate to handle actions
        UNUserNotificationCenter.current().delegate = self
        
        categoriesRegistered = true
        
        #if DEBUG
        print("NotificationManager: Categories registered")
        #endif
    }
    
    // MARK: - Notification Posting
    
    /// Posts a local notification for a confirmed detection.
    /// - Note: Permission is requested during onboarding. No request here.
    func postDetectionNotification(for event: DetectionEvent) {
        let content = UNMutableNotificationContent()
        content.title = "\(event.soundType.displayName) Detected"
        content.body = "Hactile detected a \(event.soundType.displayName.lowercased()) with \(Int(event.confidence * 100))% confidence."
        content.sound = .default
        content.categoryIdentifier = NotificationIdentifiers.detectionCategory
        
        // Time-sensitive so notifications break through Focus modes
        content.interruptionLevel = .timeSensitive
        
        // Add metadata for Siri Announce Notifications
        // Siri reads the title + body, so we keep them descriptive
        content.userInfo = [
            "soundType": event.soundType.rawValue,
            "confidence": event.confidence,
            "timestamp": event.timestamp.timeIntervalSince1970
        ]
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    
    /// Handles notification actions when tapped by the user.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case NotificationIdentifiers.acknowledgeAction:
            // User tapped Acknowledge — end the Live Activity in background
            Task { @MainActor in
                HactileLiveActivityManager.shared.acknowledgeActivity()
            }
            
            // Remove the notification from notification center
            center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
            
            #if DEBUG
            print("NotificationManager: User acknowledged detection (background)")
            #endif
            
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself (not an action)
            // This WILL open the app - that's expected behavior
            break
            
        default:
            break
        }
        
        completionHandler()
    }
    
    /// Allows notifications to display even when app is in foreground.
    /// We now ALWAYS show notifications for every detection (foreground and background).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and sound for ALL detections, even in foreground
        completionHandler([.banner, .sound, .list])
    }
}
