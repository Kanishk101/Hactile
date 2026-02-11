//
//  HactileLiveActivity.swift
//  HactileWidgetExtension
//
//  Live Activity and Dynamic Island for Hactile Sound Recognition
//
//  NOTE: Types are defined in SharedTypes.swift which is included
//  in the widget extension target.
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity Widget

struct HactileLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HactileAttributes.self) { context in
            // Lock Screen / Banner Live Activity
            LockScreenLiveActivityView(
                soundType: context.attributes.soundType,
                location: context.attributes.location,
                confidence: context.state.confidence,
                timestamp: context.state.detectionTimestamp,
                isAcknowledged: context.state.isAcknowledged
            )
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingViewWithConfidence(
                        soundType: context.attributes.soundType,
                        confidence: context.state.confidence
                    )
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(timestamp: context.state.detectionTimestamp)
                }
                
                DynamicIslandExpandedRegion(.center) {
                    ConfidenceCapsuleView(
                        soundType: context.attributes.soundType,
                        confidence: context.state.confidence
                    )
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(isAcknowledged: context.state.isAcknowledged)
                }
            } compactLeading: {
                CompactLeadingView()
            } compactTrailing: {
                CompactTrailingWaveform()
            } minimal: {
                MinimalView(soundType: context.attributes.soundType)
            }
        }
    }
}

// MARK: - Compact Leading View (Pulsing Dot)

struct CompactLeadingView: View {
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.3))
                .frame(width: 10, height: 10)
                .scaleEffect(pulseScale)
                .opacity(2.0 - pulseScale)
            
            Circle()
                .fill(Color.green)
                .frame(width: 5, height: 5)
                .shadow(color: Color.green.opacity(0.8), radius: 2)
        }
        .frame(width: 16, height: 16)
        .padding(.leading, 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.4
            }
        }
    }
}

// MARK: - Compact Trailing View (Animated Waveform using TimelineView)

struct CompactTrailingWaveform: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 2) {
            // Bar 1
            Capsule()
                .fill(Color.white.opacity(0.9))
                .frame(width: 2, height: isAnimating ? 12 : 4)
            // Bar 2
            Capsule()
                .fill(Color.white.opacity(0.9))
                .frame(width: 2, height: isAnimating ? 6 : 12)
            // Bar 3
            Capsule()
                .fill(Color.white.opacity(0.9))
                .frame(width: 2, height: isAnimating ? 10 : 5)
        }
        .frame(height: 14)
        .padding(.trailing, 4)
        .animation(
            .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Minimal View

struct MinimalView: View {
    let soundType: DetectedSoundType
    
    var body: some View {
        ZStack {
            Circle()
                .fill(soundType.glowColor.opacity(0.3))
            
            Image(systemName: soundType.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(soundType.glowColor)
        }
    }
}

// MARK: - Expanded Leading View (with Confidence)

struct ExpandedLeadingViewWithConfidence: View {
    let soundType: DetectedSoundType
    let confidence: Double
    
    private var isMonitoringMode: Bool {
        confidence < 0.01
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isMonitoringMode ? "waveform" : soundType.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isMonitoringMode ? Color.cyan : soundType.glowColor)
                .shadow(color: (isMonitoringMode ? Color.cyan : soundType.glowColor).opacity(0.5), radius: 4)
            
            Text(isMonitoringMode ? "Listening" : soundType.displayName)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(maxHeight: .infinity)  // Vertically center within the region
    }
}

// MARK: - Expanded Trailing View

struct ExpandedTrailingView: View {
    let timestamp: Date
    
    var body: some View {
        Text(relativeTimeString(from: timestamp))
            .font(.system(.caption, design: .rounded, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)  // Center vertically, align trailing
            .padding(.top, 2)
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else {
            return "\(Int(interval / 3600))h ago"
        }
    }
}

// MARK: - Confidence Capsule View

struct ConfidenceCapsuleView: View {
    let soundType: DetectedSoundType
    let confidence: Double
    
    private var isMonitoringMode: Bool {
        confidence < 0.01
    }
    
    var body: some View {
        ZStack {
            // Background capsule
            Capsule()
                .fill(Color.white.opacity(0.1))
                .frame(height: 36)
            
            // Filled confidence bar (only in detection mode)
            if !isMonitoringMode {
                GeometryReader { geometry in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    soundType.glowColor.opacity(0.8),
                                    soundType.glowColor.opacity(0.5)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * confidence)
                        .shadow(color: soundType.glowColor.opacity(0.6), radius: 15)
                }
                .frame(height: 36)
                .clipShape(Capsule())
            }
            
            // Centered icon and text
            HStack(spacing: 8) {
                Image(systemName: isMonitoringMode ? "ear.badge.waveform" : "waveform")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: (isMonitoringMode ? Color.cyan : soundType.glowColor), radius: 8)
                
                Text(isMonitoringMode ? "Listening..." : "\(Int(confidence * 100))%")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            // Border
            Capsule()
                .stroke((isMonitoringMode ? Color.cyan : soundType.glowColor).opacity(0.4), lineWidth: 0.5)
                .frame(height: 36)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Expanded Bottom View (Acknowledge Button)

struct ExpandedBottomView: View {
    let isAcknowledged: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            if !isAcknowledged {
                // Acknowledge button — opens URL scheme to dismiss the Live Activity
                Link(destination: URL(string: "hactile://acknowledge")!) {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 14, weight: .semibold))
                        
                        Text("Acknowledge")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    }
                }
                .padding(.horizontal, 8)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("Acknowledged")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Lock Screen Live Activity View

struct LockScreenLiveActivityView: View {
    let soundType: DetectedSoundType
    let location: String?
    let confidence: Double
    let timestamp: Date
    let isAcknowledged: Bool
    
    private var isMonitoringMode: Bool {
        confidence < 0.01
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            ContainerRelativeShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black,
                            (isMonitoringMode ? Color.cyan : soundType.glowColor).opacity(0.15),
                            Color.black
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Neon border
            ContainerRelativeShape()
                .stroke((isMonitoringMode ? Color.cyan : soundType.glowColor).opacity(0.5), lineWidth: 1)
            
            // Content
            VStack(spacing: 16) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill((isMonitoringMode ? Color.cyan : soundType.glowColor).opacity(0.3))
                                    .frame(width: 16, height: 16)
                                
                                Circle()
                                    .fill(isMonitoringMode ? Color.cyan : soundType.glowColor)
                                    .frame(width: 8, height: 8)
                                    .shadow(color: (isMonitoringMode ? Color.cyan : soundType.glowColor), radius: 4)
                            }
                            
                            Text(isMonitoringMode ? "Listening Active" : "Sound Detected")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(isMonitoringMode ? "Hactile is Monitoring" : "\(soundType.displayName) Detected")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    
                    Spacer()
                    
                    // Sound icon with glow
                    ZStack {
                        Circle()
                            .fill((isMonitoringMode ? Color.cyan : soundType.glowColor).opacity(0.2))
                            .frame(width: 48, height: 48)
                            .blur(radius: 8)
                        
                        Image(systemName: isMonitoringMode ? "waveform" : soundType.icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(isMonitoringMode ? Color.cyan : soundType.glowColor)
                            .shadow(color: (isMonitoringMode ? Color.cyan : soundType.glowColor).opacity(0.8), radius: 6)
                    }
                }
                
                // Confidence bar (only in detection mode)
                if !isMonitoringMode {
                    LockScreenConfidenceBar(
                        soundType: soundType,
                        confidence: confidence,
                        location: location
                    )
                } else {
                    Text("Waiting for sounds...")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Bottom info row
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        
                        Text(relativeTimeString(from: timestamp))
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if !isAcknowledged && !isMonitoringMode {
                        HStack(spacing: 4) {
                            Text("Tap to acknowledge")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    } else if isAcknowledged {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.green)
                            
                            Text("Acknowledged")
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .padding(16)
        }
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else {
            return "\(Int(interval / 3600))h ago"
        }
    }
}

// MARK: - Lock Screen Confidence Bar

struct LockScreenConfidenceBar: View {
    let soundType: DetectedSoundType
    let confidence: Double
    let location: String?
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 32)
                
                GeometryReader { geometry in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    soundType.glowColor,
                                    soundType.glowColor.opacity(0.6)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * confidence)
                        .shadow(color: soundType.glowColor.opacity(0.5), radius: 12)
                }
                .frame(height: 32)
                .clipShape(Capsule())
                
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                        
                        Text("Confidence")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.leading, 12)
                    
                    Spacer()
                    
                    Text("\(Int(confidence * 100))%")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.trailing, 12)
                }
                
                Capsule()
                    .stroke(soundType.glowColor.opacity(0.3), lineWidth: 0.5)
                    .frame(height: 32)
            }
            
            if let location = location, location != "Monitoring" {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10))
                    
                    Text(location)
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Widget Bundle

@main
struct HactileWidgetBundle: WidgetBundle {
    var body: some Widget {
        HactileLiveActivity()
    }
}
