//
//  SharedTypes.swift
//  Hactile
//
//  Type definitions for the main app target.
//

import SwiftUI
import ActivityKit

/// Represents the types of sounds Hactile can recognize.
enum DetectedSoundType: String, CaseIterable, Codable, Hashable {
    case doorbell
    case siren
    case knock
    case alarm
    case smokeAlarm
    case dogBark
    case babyCry
    case catMeow
    case waterRunning
    case speech
    case phoneRinging
    case carHorn
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .doorbell: return "Doorbell"
        case .siren: return "Siren"
        case .knock: return "Knocking"
        case .alarm: return "Alarm"
        case .smokeAlarm: return "Smoke Alarm"
        case .dogBark: return "Dog Bark"
        case .babyCry: return "Baby Cry"
        case .catMeow: return "Cat Meow"
        case .waterRunning: return "Water Running"
        case .speech: return "Speech"
        case .phoneRinging: return "Phone Ringing"
        case .carHorn: return "Car Horn"
        }
    }
    
    /// SF Symbol icon name
    var icon: String {
        switch self {
        case .doorbell: return "bell.fill"
        case .siren: return "light.beacon.max.fill"
        case .knock: return "hand.raised.fill"
        case .alarm: return "alarm.fill"
        case .smokeAlarm: return "smoke.fill"
        case .dogBark: return "dog.fill"
        case .babyCry: return "figure.and.child.holdinghands"
        case .catMeow: return "cat.fill"
        case .waterRunning: return "drop.fill"
        case .speech: return "person.wave.2.fill"
        case .phoneRinging: return "phone.fill"
        case .carHorn: return "car.fill"
        }
    }
    
    /// Glow color for active state
    var glowColor: Color {
        switch self {
        case .doorbell: return Color(red: 0.4, green: 0.8, blue: 1.0)
        case .siren: return Color(red: 1.0, green: 0.4, blue: 0.3)
        case .knock: return Color(red: 0.7, green: 0.5, blue: 1.0)
        case .alarm: return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .smokeAlarm: return Color(red: 1.0, green: 0.3, blue: 0.1)
        case .dogBark: return Color(red: 0.5, green: 0.9, blue: 0.5)
        case .babyCry: return Color(red: 1.0, green: 0.6, blue: 0.8)
        case .catMeow: return Color(red: 0.9, green: 0.7, blue: 0.4)
        case .waterRunning: return Color(red: 0.3, green: 0.7, blue: 1.0)
        case .speech: return Color(red: 0.6, green: 0.8, blue: 0.4)
        case .phoneRinging: return Color(red: 0.3, green: 0.9, blue: 0.6)
        case .carHorn: return Color(red: 1.0, green: 0.85, blue: 0.3)
        }
    }
    
    /// The primary SoundAnalysis classifier label
    var classifierLabel: String {
        switch self {
        case .doorbell: return "door_bell"
        case .siren: return "siren"
        case .knock: return "knock"
        case .alarm: return "fire_alarm"
        case .smokeAlarm: return "smoke_detector"
        case .dogBark: return "dog"
        case .babyCry: return "crying_baby"
        case .catMeow: return "cat"
        case .waterRunning: return "water_tap_faucet"
        case .speech: return "speech"
        case .phoneRinging: return "telephone_bell_ringing"
        case .carHorn: return "car_horn"
        }
    }
    
    var confidenceThreshold: Double {
        switch self {
        case .siren: return 0.50
        case .smokeAlarm: return 0.45
        case .alarm: return 0.50
        case .babyCry: return 0.45
        case .carHorn: return 0.70      // Raised — false positives from water at 0.57-0.67, real car horns at 0.79+
        case .doorbell: return 0.50
        case .dogBark: return 0.50
        case .catMeow: return 0.50
        case .phoneRinging: return 0.65  // Raised — false positives from alarm at 0.59-0.73, real phone at 0.78+
        case .knock: return 0.55
        case .waterRunning: return 0.50  // Lowered — so it appears in candidate tracking early to suppress carHorn
        case .speech: return 0.50
        }
    }
    
    /// Number of consecutive above-threshold frames required to confirm detection.
    /// Urgent/rare sounds need fewer frames; common/continuous sounds need more.
    var requiredFrames: Int {
        switch self {
        // Urgent safety — short burst, react fast
        case .smokeAlarm: return 1
        case .siren: return 1
        case .babyCry: return 1
        // Moderately urgent — a couple of confirmations
        case .alarm: return 2
        case .carHorn: return 2
        case .doorbell: return 2
        case .knock: return 2
        // Common / continuous — need more proof
        case .dogBark: return 3
        case .catMeow: return 3
        case .phoneRinging: return 3
        case .waterRunning: return 3
        case .speech: return 2
        }
    }
    
    /// Defines which OTHER types this sound type takes priority over when both
    /// are detected simultaneously. This resolves known Apple classifier confusion pairs.
    /// If type A dominates type B, then: A can never be suppressed by B, and B IS suppressed when A is present.
    var dominatesOver: Set<DetectedSoundType> {
        switch self {
        case .waterRunning: return [.carHorn]     // Water noise gets misclassified as car horn
        case .alarm: return [.phoneRinging]        // Alarm ringtones get misclassified as phone ringing
        case .smokeAlarm: return [.siren, .alarm]  // Smoke alarm takes priority over generic alarm/siren
        case .siren: return [.alarm]               // Siren over generic alarm
        default: return []
        }
    }
    
    /// Initialize from a classifier result label.
    /// Handles Apple's exact labels AND common aliases/variations.
    init?(classifierLabel: String) {
        let normalized = classifierLabel
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        
        let aliases: [String: DetectedSoundType] = [
            // Doorbell
            "door_bell": .doorbell,
            "doorbell": .doorbell,
            "doorbell_ring": .doorbell,
            "ding_dong": .doorbell,
            
            // Siren
            "siren": .siren,
            "civil_defense_siren": .siren,
            "police_siren": .siren,
            "ambulance_siren": .siren,
            "fire_engine_siren": .siren,
            "emergency_vehicle": .siren,
            
            // Knock
            "knock": .knock,
            "knocking": .knock,
            "door_knock": .knock,
            "tap": .knock,
            "thump_thud": .knock,
            
            // Alarm
            "fire_alarm": .alarm,
            "alarm": .alarm,
            "alarm_clock": .alarm,
            "clock_alarm": .alarm,
            "buzzer": .alarm,
            "reverse_beeps": .alarm,
            "beep": .alarm,
            
            // Smoke Alarm
            "smoke_detector": .smokeAlarm,
            "smoke_alarm": .smokeAlarm,
            
            // Dog
            "dog": .dogBark,
            "dog_bark": .dogBark,
            "dog_bow_wow": .dogBark,
            "dog_growl": .dogBark,
            "dog_howl": .dogBark,
            "dog_whimper": .dogBark,
            
            // Baby cry
            "crying_baby": .babyCry,
            "baby_crying": .babyCry,
            "crying_sobbing": .babyCry,
            "baby_laughter": .babyCry,
            
            // Cat
            "cat": .catMeow,
            "cat_meow": .catMeow,
            "cat_purr": .catMeow,
            "meow": .catMeow,
            
            // Water running
            "water_tap_faucet": .waterRunning,
            "water": .waterRunning,
            "bathtub_filling_washing": .waterRunning,
            "sink_filling_washing": .waterRunning,
            "liquid_dripping": .waterRunning,
            "liquid_filling_container": .waterRunning,
            "liquid_pouring": .waterRunning,
            "liquid_trickle_dribble": .waterRunning,
            "boiling": .waterRunning,
            
            // Speech
            "speech": .speech,
            "babble": .speech,
            "chatter": .speech,
            "shout": .speech,
            "yell": .speech,
            "whispering": .speech,
            "screaming": .speech,
            "children_shouting": .speech,
            
            // Phone ringing
            "telephone_bell_ringing": .phoneRinging,
            "telephone": .phoneRinging,
            "ringtone": .phoneRinging,
            
            // Car horn
            "car_horn": .carHorn,
            "honking": .carHorn,
            "vehicle_skidding": .carHorn,
            "air_horn": .carHorn,
            "bicycle_bell": .carHorn,
        ]
        
        if let direct = aliases[normalized] {
            self = direct
            return
        }
        
        // Fallback: substring matching
        let containsMap: [(String, DetectedSoundType)] = [
            ("door_bell", .doorbell),
            ("siren", .siren),
            ("fire_alarm", .alarm),
            ("smoke_detector", .smokeAlarm),
            ("car_horn", .carHorn),
            ("alarm", .alarm),
            ("crying_baby", .babyCry),
            ("telephone", .phoneRinging),
        ]
        
        for (substring, type) in containsMap {
            if normalized.contains(substring) {
                self = type
                return
            }
        }
        
        return nil
    }
}

/// ActivityKit attributes for Live Activities.
struct HactileAttributes: ActivityAttributes {
    
    public struct ContentState: Codable, Hashable {
        var confidence: Double
        var detectionTimestamp: Date
        var isAcknowledged: Bool
    }
    
    var soundType: DetectedSoundType
    var location: String?
}
