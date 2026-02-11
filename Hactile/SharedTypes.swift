//
//  SharedTypes.swift
//  Hactile
//
//  Type definitions for the main app target.
//

import SwiftUI
import ActivityKit

// MARK: - Detected Sound Type

/// Represents the types of sounds Hactile can recognize.
/// Used by SoundRecognitionManager, HapticManager, Live Activities, and UI.
///
/// This enum is defined once here and shared across all targets to avoid
/// "ambiguous type lookup" errors when the same type is defined in multiple places.
///
/// Labels are mapped to Apple's SNClassifierIdentifier.version1 taxonomy.
/// Use `knownClassifications` on an `SNClassifySoundRequest` to see full list.
enum DetectedSoundType: String, CaseIterable, Codable, Hashable {
    // Original 6 sound types
    case doorbell
    case siren
    case knock
    case alarm
    case dogBark
    case babyCry
    
    // Additional useful sound types from Apple's classifier
    case carHorn
    case glassBreak
    case gunshot
    case catMeow
    case waterRunning
    case speech
    case applause
    case cough
    case whistle
    
    /// Human-readable display name
    var displayName: String {
        switch self {
        case .doorbell: return "Doorbell"
        case .siren: return "Siren"
        case .knock: return "Knocking"
        case .alarm: return "Alarm"
        case .dogBark: return "Dog Bark"
        case .babyCry: return "Baby Cry"
        case .carHorn: return "Car Horn"
        case .glassBreak: return "Glass Break"
        case .gunshot: return "Gunshot"
        case .catMeow: return "Cat Meow"
        case .waterRunning: return "Water Running"
        case .speech: return "Speech"
        case .applause: return "Applause"
        case .cough: return "Cough"
        case .whistle: return "Whistle"
        }
    }
    
    /// SF Symbol icon name
    var icon: String {
        switch self {
        case .doorbell: return "bell.fill"
        case .siren: return "light.beacon.max.fill"
        case .knock: return "hand.raised.fill"
        case .alarm: return "alarm.fill"
        case .dogBark: return "dog.fill"
        case .babyCry: return "figure.and.child.holdinghands"
        case .carHorn: return "car.fill"
        case .glassBreak: return "shield.lefthalf.filled.trianglebadge.exclamationmark"
        case .gunshot: return "exclamationmark.triangle.fill"
        case .catMeow: return "cat.fill"
        case .waterRunning: return "drop.fill"
        case .speech: return "person.wave.2.fill"
        case .applause: return "hands.clap.fill"
        case .cough: return "lungs.fill"
        case .whistle: return "music.note"
        }
    }
    
    /// Accent/glow color for UI elements
    var glowColor: Color {
        switch self {
        case .doorbell: return Color(red: 0.4, green: 0.8, blue: 1.0)
        case .siren: return Color(red: 1.0, green: 0.4, blue: 0.3)
        case .knock: return Color(red: 0.7, green: 0.5, blue: 1.0)
        case .alarm: return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .dogBark: return Color(red: 0.5, green: 0.9, blue: 0.5)
        case .babyCry: return Color(red: 1.0, green: 0.6, blue: 0.8)
        case .carHorn: return Color(red: 1.0, green: 0.85, blue: 0.3)
        case .glassBreak: return Color(red: 0.95, green: 0.3, blue: 0.3)
        case .gunshot: return Color(red: 0.9, green: 0.2, blue: 0.2)
        case .catMeow: return Color(red: 0.9, green: 0.7, blue: 0.4)
        case .waterRunning: return Color(red: 0.3, green: 0.7, blue: 1.0)
        case .speech: return Color(red: 0.6, green: 0.8, blue: 0.4)
        case .applause: return Color(red: 1.0, green: 0.75, blue: 0.5)
        case .cough: return Color(red: 0.8, green: 0.6, blue: 0.7)
        case .whistle: return Color(red: 0.5, green: 0.9, blue: 0.9)
        }
    }
    
    /// The primary identifier used by Apple's Sound Classification model (version1).
    /// These map directly to SNClassifierIdentifier.version1 taxonomy labels.
    var classifierLabel: String {
        switch self {
        case .doorbell: return "door_bell"
        case .siren: return "siren"
        case .knock: return "knock"
        case .alarm: return "fire_alarm"
        case .dogBark: return "dog"
        case .babyCry: return "crying_baby"
        case .carHorn: return "car_horn"
        case .glassBreak: return "glass"
        case .gunshot: return "gunshot_gunfire"
        case .catMeow: return "cat"
        case .waterRunning: return "water_tap_faucet"
        case .speech: return "speech"
        case .applause: return "applause"
        case .cough: return "cough"
        case .whistle: return "whistle"
        }
    }
    
    /// Per-sound confidence threshold for detection.
    /// Tuned for Apple's version1 classifier which uses broad AudioSet labels.
    /// Lower thresholds = higher recall (fewer misses), more false positives.
    /// Higher thresholds = higher precision (fewer false alarms), more misses.
    var confidenceThreshold: Double {
        switch self {
        // Safety-critical: lowest thresholds (we'd rather false-alarm than miss)
        case .siren: return 0.40
        case .alarm: return 0.45
        case .gunshot: return 0.40
        case .glassBreak: return 0.45
        case .babyCry: return 0.45
        // Standard sounds
        case .doorbell: return 0.50
        case .dogBark: return 0.50
        case .carHorn: return 0.50
        case .catMeow: return 0.50
        // Higher thresholds for common/frequent sounds (reduce noise)
        case .knock: return 0.55
        case .waterRunning: return 0.55
        case .speech: return 0.60
        case .applause: return 0.55
        case .cough: return 0.55
        case .whistle: return 0.55
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
        
        // Comprehensive alias mapping for Apple's version1 taxonomy
        let aliases: [String: DetectedSoundType] = [
            // Doorbell
            "door_bell": .doorbell,
            "doorbell": .doorbell,
            "doorbell_ring": .doorbell,
            "ding_dong": .doorbell,
            "ding_dong_(bell)": .doorbell,
            
            // Siren
            "siren": .siren,
            "civil_defense_siren": .siren,
            "police_car_(siren)": .siren,
            "ambulance_(siren)": .siren,
            "fire_engine,_fire_truck_(siren)": .siren,
            "emergency_vehicle": .siren,
            "police_siren": .siren,
            "ambulance_siren": .siren,
            "fire_truck_siren": .siren,
            
            // Knock
            "knock": .knock,
            "knocking": .knock,
            "door_knock": .knock,
            "tap": .knock,
            "tapping": .knock,
            
            // Alarm
            "fire_alarm": .alarm,
            "smoke_detector,_smoke_alarm": .alarm,
            "smoke_detector": .alarm,
            "smoke_alarm": .alarm,
            "alarm": .alarm,
            "alarm_clock": .alarm,
            "clock_alarm": .alarm,
            "buzzer": .alarm,
            "reversing_beeps": .alarm,
            "beep,_bleep": .alarm,
            
            // Dog
            "dog": .dogBark,
            "dog_bark": .dogBark,
            "dog_barking": .dogBark,
            "bark": .dogBark,
            "bow_wow": .dogBark,
            "howl": .dogBark,
            "growling": .dogBark,
            "yip": .dogBark,
            
            // Baby cry
            "crying_baby": .babyCry,
            "baby_crying": .babyCry,
            "baby_cry": .babyCry,
            "baby": .babyCry,
            "infant_crying": .babyCry,
            "child_crying": .babyCry,
            "whimper_(baby)": .babyCry,
            
            // Car horn
            "car_horn": .carHorn,
            "honking": .carHorn,
            "vehicle_horn,_car_horn,_honking": .carHorn,
            "truck_horn": .carHorn,
            "beep,_horn": .carHorn,
            "bicycle_bell": .carHorn,
            
            // Glass break
            "glass": .glassBreak,
            "glass_breaking": .glassBreak,
            "shatter": .glassBreak,
            "breaking": .glassBreak,
            "smash": .glassBreak,
            
            // Gunshot
            "gunshot_gunfire": .gunshot,
            "gunshot,_gunfire": .gunshot,
            "gunshot": .gunshot,
            "gunfire": .gunshot,
            "explosion": .gunshot,
            "firecracker": .gunshot,
            
            // Cat
            "cat": .catMeow,
            "meow": .catMeow,
            "cat_meow": .catMeow,
            "purr": .catMeow,
            "hiss": .catMeow,
            "caterwaul": .catMeow,
            
            // Water running
            "water_tap_faucet": .waterRunning,
            "water_tap,_faucet": .waterRunning,
            "water": .waterRunning,
            "bathtub_(filling_or_washing)": .waterRunning,
            "sink_(filling_or_washing)": .waterRunning,
            "pour": .waterRunning,
            "fill_(with_liquid)": .waterRunning,
            "drip": .waterRunning,
            
            // Speech
            "speech": .speech,
            "male_speech,_man_speaking": .speech,
            "female_speech,_woman_speaking": .speech,
            "child_speech,_kid_speaking": .speech,
            "conversation": .speech,
            "narration,_monologue": .speech,
            "male_speech": .speech,
            "female_speech": .speech,
            "child_speech": .speech,
            "shouting": .speech,
            "yell": .speech,
            "whispering": .speech,
            
            // Applause
            "applause": .applause,
            "clapping": .applause,
            "cheering": .applause,
            "crowd": .applause,
            
            // Cough
            "cough": .cough,
            "coughing": .cough,
            "sneeze": .cough,
            "sneezing": .cough,
            "throat_clearing": .cough,
            
            // Whistle
            "whistle": .whistle,
            "whistling": .whistle,
            "whip": .whistle,
        ]
        
        if let direct = aliases[normalized] {
            self = direct
            return
        }
        
        // Fallback: check if the normalized label CONTAINS any of the primary classifier labels
        // This catches compound labels like "domestic_animals,_pets" → dog
        let containsMap: [(String, DetectedSoundType)] = [
            ("door_bell", .doorbell),
            ("siren", .siren),
            ("fire_alarm", .alarm),
            ("smoke_detector", .alarm),
            ("alarm", .alarm),
            ("gunshot", .gunshot),
            ("crying_baby", .babyCry),
            ("car_horn", .carHorn),
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

// MARK: - Activity Attributes

/// ActivityKit attributes for Hactile Live Activities.
/// Defines the static and dynamic data for Dynamic Island and Lock Screen.
struct HactileAttributes: ActivityAttributes {
    
    /// Dynamic content state that can be updated
    public struct ContentState: Codable, Hashable {
        var confidence: Double
        var detectionTimestamp: Date
        var isAcknowledged: Bool
    }
    
    /// Static attributes set when activity starts
    var soundType: DetectedSoundType
    var location: String?
}
