//
//  ContentView.swift
//  Hactile
//
//  A privacy-first sound recognition app for the Swift Student Challenge
//
//  ## Architecture Notes
//  This view is the UI layer only. It REACTS to state changes from managers
//  rather than driving business logic. This separation ensures:
//  1. Testability - managers can be tested independently
//  2. Clarity - each component has a single responsibility
//  3. Maintainability - changes to one layer don't cascade
//

import SwiftUI
import UIKit
import Combine
import Foundation

// MARK: - Animated Background

struct AnimatedMeshBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/60)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let animatedPhase = CGFloat(now.truncatingRemainder(dividingBy: 20)) / 20
                
                // Base gradient - Midnight Blue to Slate
                let baseGradient = Gradient(colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.15),
                    Color(red: 0.08, green: 0.10, blue: 0.18),
                    Color(red: 0.06, green: 0.07, blue: 0.14)
                ])
                
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        baseGradient,
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )
                
                // Animated orbs
                let orbPositions: [(CGFloat, CGFloat, Color, CGFloat)] = [
                    (0.2, 0.3, Color(red: 0.15, green: 0.2, blue: 0.4), 0.4),
                    (0.8, 0.2, Color(red: 0.2, green: 0.15, blue: 0.35), 0.35),
                    (0.5, 0.7, Color(red: 0.12, green: 0.18, blue: 0.38), 0.45),
                    (0.3, 0.85, Color(red: 0.18, green: 0.12, blue: 0.32), 0.3),
                    (0.75, 0.65, Color(red: 0.14, green: 0.16, blue: 0.36), 0.38)
                ]
                
                for (index, orb) in orbPositions.enumerated() {
                    let phaseOffset = CGFloat(index) * 0.2
                    let phase = Double((animatedPhase + phaseOffset) * .pi * 2)
                    let breathingScale = 1.0 + CGFloat(sin(phase)) * 0.15
                    let xOffset = CGFloat(sin(phase)) * 30
                    let yOffset = CGFloat(cos(phase)) * 20
                    
                    let centerX = orb.0 * size.width + xOffset
                    let centerY = orb.1 * size.height + yOffset
                    let radius = size.width * orb.3 * breathingScale
                    
                    let orbGradient = Gradient(colors: [
                        orb.2.opacity(0.6),
                        orb.2.opacity(0.0)
                    ])
                    
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: centerX - radius,
                            y: centerY - radius,
                            width: radius * 2,
                            height: radius * 2
                        )),
                        with: .radialGradient(
                            orbGradient,
                            center: CGPoint(x: centerX, y: centerY),
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass Card Modifier

struct GlassCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 24
    var isHighlighted: Bool = false
    var accentColor: Color = .white
    
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if isHighlighted {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(accentColor.opacity(0.15))
                                .animation(.easeInOut(duration: 0.3), value: isHighlighted)
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHighlighted ? 0.4 : 0.15),
                                Color.white.opacity(isHighlighted ? 0.2 : 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
                    .animation(.easeInOut(duration: 0.3), value: isHighlighted)
            }
            .shadow(color: isHighlighted ? accentColor.opacity(0.3) : .clear, radius: 20, x: 0, y: 0)
            .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 24, isHighlighted: Bool = false, accentColor: Color = .white) -> some View {
        modifier(GlassCardStyle(cornerRadius: cornerRadius, isHighlighted: isHighlighted, accentColor: accentColor))
    }
}

// MARK: - Pulse Header

struct PulseHeader: View {
    let isListening: Bool
    @State private var rippleScale: CGFloat = 1.0
    @State private var rippleOpacity: CGFloat = 0.6
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if isListening {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            .frame(width: 12, height: 12)
                            .scaleEffect(rippleScale + CGFloat(index) * 0.5)
                            .opacity(rippleOpacity - Double(index) * 0.2)
                    }
                }
                
                Circle()
                    .fill(isListening ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                    .shadow(color: isListening ? Color.green.opacity(0.6) : .clear, radius: 4)
            }
            .frame(width: 24, height: 24)
            
            Text(isListening ? "Listening Active" : "Paused")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(isListening ? .primary : .secondary)
                .animation(.easeOut(duration: 0.2), value: isListening)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: isListening ? nil : 120)
        .glassCard(cornerRadius: 20, isHighlighted: isListening, accentColor: .green)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isListening)
        .onAppear {
            if isListening { startRippleAnimation() }
        }
        .onChange(of: isListening) { _, newValue in
            if newValue { 
                startRippleAnimation() 
            } else {
                rippleScale = 1.0
                rippleOpacity = 0.0
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isListening ? "Listening active" : "Listening paused")
    }
    
    private func startRippleAnimation() {
        rippleScale = 1.0
        rippleOpacity = 0.6
        withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
            rippleScale = 3.0
            rippleOpacity = 0.0
        }
    }
}

// MARK: - Live Waveform

struct LiveWaveform: View {
    let isActive: Bool
    @State private var barHeights: [CGFloat] = [0.3, 0.5, 0.3]
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.8), Color.white.opacity(0.4)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 3, height: isActive ? 12 * barHeights[index] : 4)
                    .animation(.easeInOut(duration: 0.2), value: barHeights[index])
                    .animation(.easeOut(duration: 0.15), value: isActive)
            }
        }
        .frame(height: 16)
        .onReceive(timer) { _ in
            guard isActive else { return }
            barHeights = [
                CGFloat.random(in: 0.3...1.0),
                CGFloat.random(in: 0.4...1.0),
                CGFloat.random(in: 0.3...1.0)
            ]
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Sound Card

struct SoundCard: View {
    let sound: SoundCardData
    let isListening: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ZStack {
                        if sound.isActive && isListening {
                            Circle()
                                .fill(sound.accentColor.opacity(0.3))
                                .frame(width: 48, height: 48)
                                .blur(radius: 12)
                                .animation(.easeInOut(duration: 0.3), value: sound.isActive && isListening)
                        }
                        
                        Image(systemName: sound.icon)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(sound.isActive ? sound.accentColor : .secondary)
                            .frame(width: 48, height: 48)
                            .animation(.easeInOut(duration: 0.2), value: sound.isActive)
                    }
                    
                    Spacer()
                    
                    if sound.isActive && isListening {
                        LiveWaveform(isActive: true)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(sound.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text(sound.isActive ? (isListening ? "Monitoring" : "Enabled") : "Tap to enable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .animation(.easeInOut(duration: 0.2), value: sound.isActive)
                        .animation(.easeInOut(duration: 0.2), value: isListening)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .glassCard(cornerRadius: 24, isHighlighted: sound.isActive, accentColor: sound.accentColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sound.name) detection \(sound.isActive ? "enabled" : "disabled")")
        .accessibilityHint("Double tap to \(sound.isActive ? "disable" : "enable")")
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Sound Card Data Model

struct SoundCardData: Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let accentColor: Color
    let soundType: DetectedSoundType
    var isActive: Bool
}

// MARK: - Sound Matrix

struct SoundMatrix: View {
    let sounds: [SoundCardData]
    let isListening: Bool
    let onToggle: (Int) -> Void
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(Array(sounds.enumerated()), id: \.element.id) { index, sound in
                SoundCard(sound: sound, isListening: isListening) {
                    onToggle(index)
                }
            }
        }
    }
}

// MARK: - Sliding Toggle

// MARK: - Slider Track Background

private struct SliderTrackBackground: View {
    let progress: CGFloat
    let trackWidth: CGFloat
    let trackHeight: CGFloat
    
    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay {
                sliderFillOverlay
            }
            .overlay {
                sliderStrokeOverlay
            }
            .frame(width: trackWidth, height: trackHeight)
    }
    
    private var sliderFillOverlay: some View {
        GeometryReader { _ in
            Capsule()
                .fill(LinearGradient(
                    colors: [Color.green.opacity(0.3 * progress), Color.green.opacity(0.1 * progress)],
                    startPoint: .leading, endPoint: .trailing
                ))
        }
    }
    
    private var sliderStrokeOverlay: some View {
        Capsule()
            .stroke(LinearGradient(
                colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ), lineWidth: 0.5)
    }
}

// MARK: - Slider Knob View

private struct SliderKnobView: View {
    let isOn: Bool
    let progress: CGFloat
    let knobSize: CGFloat
    let waveformPhase: CGFloat
    
    var body: some View {
        ZStack {
            knobGlow
            knobBody
            knobIcon
        }
    }
    
    private var knobGlow: some View {
        Circle()
            .fill(Color.green.opacity(0.3 * progress))
            .frame(width: knobSize + 8, height: knobSize + 8)
            .blur(radius: 8)
    }
    
    private var knobBody: some View {
        Circle()
            .fill(.regularMaterial)
            .frame(width: knobSize, height: knobSize)
            .overlay {
                Circle()
                    .stroke(LinearGradient(
                        colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ), lineWidth: 0.5)
            }
            .shadow(color: Color.green.opacity(0.2 * progress), radius: 10)
    }
    
    private var knobIcon: some View {
        let phase = Double(waveformPhase)
        let scaleValue = 1.0 + CGFloat(sin(phase)) * 0.05
        let opacityValue = 0.9 + Double(sin(phase)) * 0.08
        
        return Image(systemName: isOn ? "waveform" : "chevron.right")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(isOn ? .green : .secondary)
            .scaleEffect(isOn ? scaleValue : 1.0)
            .opacity(isOn ? opacityValue : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isOn)
    }
}

// MARK: - Slider Text Label

private struct SliderTextLabel: View {
    let isOn: Bool
    let isDragging: Bool
    let knobSize: CGFloat
    let trackWidth: CGFloat
    
    private var textOpacity: Double { isOn ? 0.6 : 0.7 }
    
    // 🎯 ADJUST THIS VALUE to move text left/right
    private let textLeadingOffset: CGFloat = 105  // Increase = moves text right, Decrease = moves text left
    
    var body: some View {
        HStack {
            Spacer()
                .frame(width: textLeadingOffset)  // 🎯 LEFT SPACING - Change textLeadingOffset above
            
            Text(isOn ? "Listening" : "Slide to Listen")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .opacity(isDragging ? 0.3 : textOpacity)
            
            Spacer()
        }
        .frame(width: trackWidth)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isOn)
    }
}

struct SlidingToggle: View {
    @Binding var isOn: Bool
    var onChanged: ((Bool) -> Void)?
    
    @State private var knobPosition: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var lastHapticStep: Int = -1
    @State private var waveformPhase: CGFloat = 0
    
    private let waveformAnimation = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)
    
    private let trackWidth: CGFloat = 280
    private let knobSize: CGFloat = 56
    private let padding: CGFloat = 4
    
    private var maxOffset: CGFloat { trackWidth - knobSize - (padding * 2) }
    
    private var progress: CGFloat {
        min(max(knobPosition / maxOffset, 0), 1)
    }
    
    var body: some View {
        ZStack {
            SliderTrackBackground(
                progress: progress,
                trackWidth: trackWidth,
                trackHeight: knobSize + (padding * 2)
            )
            
            // Text layer centered absolutely in the capsule
            SliderTextLabel(
                isOn: isOn,
                isDragging: isDragging,
                knobSize: knobSize,
                trackWidth: trackWidth
            )
            .frame(width: trackWidth, alignment: .center)
            
            knobLayer
        }
        .onAppear {
            knobPosition = isOn ? maxOffset : 0
            if isOn {
                withAnimation(waveformAnimation) {
                    waveformPhase = .pi * 2
                }
            }
        }
        .onChange(of: isOn) { _, newValue in
            handleIsOnChange(newValue)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isOn ? "Sound monitoring active" : "Sound monitoring paused")
        .accessibilityHint("Slide to \(isOn ? "pause" : "activate")")
        .accessibilityAddTraits(.isButton)
    }
    
    private var knobLayer: some View {
        HStack {
            SliderKnobView(
                isOn: isOn,
                progress: progress,
                knobSize: knobSize,
                waveformPhase: waveformPhase
            )
            .offset(x: knobPosition)
            .gesture(dragGesture)
            Spacer()
        }
        .padding(.leading, padding)
        .frame(width: trackWidth)
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                let startPosition = isOn ? maxOffset : 0
                let newPosition = startPosition + value.translation.width
                knobPosition = min(max(newPosition, 0), maxOffset)
                
                let currentStep = Int(progress * 10)
                if currentStep != lastHapticStep {
                    lastHapticStep = currentStep
                    HapticManager.shared.playSelection()
                }
            }
            .onEnded { _ in
                handleDragEnd()
            }
    }
    
    private func handleDragEnd() {
        isDragging = false
        lastHapticStep = -1
        let shouldActivate = knobPosition > maxOffset * 0.5
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            knobPosition = shouldActivate ? maxOffset : 0
        }
        
        if shouldActivate != isOn {
            isOn = shouldActivate
            HapticManager.shared.playNotification(shouldActivate ? .success : .warning)
            onChanged?(shouldActivate)
        }
    }
    
    private func handleIsOnChange(_ newValue: Bool) {
        if !isDragging {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                knobPosition = newValue ? maxOffset : 0
            }
        }
        if newValue {
            withAnimation(waveformAnimation) {
                waveformPhase = .pi * 2
            }
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                waveformPhase = 0
            }
        }
    }
}

// MARK: - Dashboard Header

struct DashboardHeader: View {
    let isListening: Bool
    var onSimulateTap: () -> Void
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hactile")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .onTapGesture(count: 2) {
                        // Hidden simulation trigger for demos
                        onSimulateTap()
                    }
                
                Text("Sound Recognition")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            PulseHeader(isListening: isListening)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hactile, Sound Recognition App")
    }
}



// MARK: - Active Sounds Summary

struct ActiveSoundsSummary: View {
    let activeCount: Int
    let activeNames: String
    let isListening: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "ear.badge.waveform")
                .font(.system(size: 20))
                .foregroundStyle(isListening ? .green : .secondary)
                .animation(.easeOut(duration: 0.2), value: isListening)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(isListening ? "Monitoring \(activeCount) sounds" : "Monitoring paused")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize()
                    .frame(minWidth: 180, alignment: .leading)
                    .animation(.easeOut(duration: 0.2), value: isListening)
                    .animation(.easeOut(duration: 0.2), value: activeCount)
                
                if activeCount > 0 && isListening {
                    Text(activeNames)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                }
            }
            .animation(.easeOut(duration: 0.25), value: isListening)
            .animation(.easeOut(duration: 0.2), value: activeNames)
            
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .glassCard(cornerRadius: 16, isHighlighted: isListening, accentColor: .green)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isListening)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isListening ? "Monitoring \(activeCount) sounds" : "Monitoring paused")
    }
}

// MARK: - Content View

// MARK: - Scroll shadow

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Error Card View

private struct ErrorCardView: View {
    let error: Error
    let onRetry: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error.localizedDescription)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                Button("Retry") {
                    onRetry()
                }
                .font(.system(size: 14, weight: .semibold))
                
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 14, weight: .semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 12, isHighlighted: false, accentColor: .red)
        .accessibilityLabel("Error: \(error.localizedDescription)")
    }
}

// MARK: - Scroll Content View

private struct ScrollContentView: View {
    let activeSoundsCount: Int
    let activeNames: String
    let isListening: Bool
    let currentError: Error?
    let soundCards: [SoundCardData]
    let onToggleSound: (Int) -> Void
    let onRetry: () -> Void
    let onShowPermissionHelp: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            GeometryReader { geo in
                Color.clear
                    .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("scroll")).minY)
            }
            .frame(height: 0)
            
            ActiveSoundsSummary(
                activeCount: activeSoundsCount,
                activeNames: activeNames,
                isListening: isListening
            )
            .onLongPressGesture {
                onShowPermissionHelp()
            }
        
            if let error = currentError {
                ErrorCardView(error: error, onRetry: onRetry)
            }
            
            SoundDetectionHeader(
                activeCount: activeSoundsCount,
                totalCount: soundCards.count
            )
            
            SoundMatrix(
                sounds: soundCards,
                isListening: isListening,
                onToggle: onToggleSound
            )
            
            Color.clear.frame(height: 100)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Sound Detection Header

private struct SoundDetectionHeader: View {
    let activeCount: Int
    let totalCount: Int
    
    var body: some View {
        HStack {
            Text("Sound Detection")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text("\(activeCount)/\(totalCount)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

// MARK: - Scroll Edge Fade

private struct ScrollBlurOverlay: View {
    let showTopBlur: Bool
    
    // Dark tone matching the mesh background
    private let fadeColor = Color(red: 0.05, green: 0.03, blue: 0.12)
    
    var body: some View {
        VStack(spacing: 0) {
            // Top fade — smooth multi-stop gradient
            LinearGradient(
                stops: [
                    .init(color: fadeColor.opacity(0.9), location: 0.0),
                    .init(color: fadeColor.opacity(0.6), location: 0.3),
                    .init(color: fadeColor.opacity(0.2), location: 0.7),
                    .init(color: fadeColor.opacity(0.0), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
            .opacity(showTopBlur ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.25), value: showTopBlur)
            .allowsHitTesting(false)
            
            Spacer()
            
            // Bottom fade — subtle, larger region
            LinearGradient(
                stops: [
                    .init(color: fadeColor.opacity(0.0), location: 0.0),
                    .init(color: fadeColor.opacity(0.15), location: 0.3),
                    .init(color: fadeColor.opacity(0.4), location: 0.7),
                    .init(color: fadeColor.opacity(0.6), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

struct ContentView: View {
    // MARK: - Manager References
    // Using shared singleton instances - NOT creating new ones
    // This ensures all components share the same state
    
    @StateObject private var soundManager = SoundRecognitionManager.shared
    @StateObject private var liveActivityManager = HactileLiveActivityManager.shared
    
    // MARK: - Local UI State
    
    @State private var soundCards: [SoundCardData] = []
    @State private var showSimulationPicker: Bool = false
    @State private var showPermissionHelp: Bool = false
    
    // MARK: - Scroll Shadow
    
    @State private var scrollOffset: CGFloat = 0
    
    // MARK: - Computed Properties
    
    private var listeningBinding: Binding<Bool> {
        Binding(
            get: { soundManager.isListening },
            set: { newValue in
                handleListeningToggle(newValue)
            }
        )
    }
    
    private var activeSounds: [SoundCardData] {
        soundCards.filter(\.isActive)
    }
    
    private var activeNames: String {
        activeSounds.map(\.name).joined(separator: ", ")
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            AnimatedMeshBackground()
            
            mainContent
            
            sliderOverlay
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: setupInitialState)
        .confirmationDialog("Simulate Sound", isPresented: $showSimulationPicker) {
            ForEach(DetectedSoundType.allCases, id: \.self) { sound in
                Button(sound.displayName) {
                    simulateSound(sound)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Select a sound to simulate for testing")
        }
        .sheet(isPresented: $showPermissionHelp) {
            PermissionHelpView()
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            DashboardHeader(isListening: soundManager.isListening, onSimulateTap: {
                showSimulationPicker = true
            })
            .padding(.top, 20)
            .padding(.horizontal, 20)
            
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    ScrollContentView(
                        activeSoundsCount: activeSounds.count,
                        activeNames: activeNames,
                        isListening: soundManager.isListening,
                        currentError: soundManager.currentError,
                        soundCards: soundCards,
                        onToggleSound: toggleSound,
                        onRetry: { handleListeningToggle(true) },
                        onShowPermissionHelp: { showPermissionHelp = true }
                    )
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetKey.self) { value in
                    scrollOffset = -value
                }
                
                ScrollBlurOverlay(showTopBlur: scrollOffset > 4)
            }
        }
    }
    
    // MARK: - Slider Overlay
    
    private var sliderOverlay: some View {
        VStack {
            Spacer()
            SlidingToggle(isOn: listeningBinding, onChanged: nil)
                .padding(.bottom, 16)
        }
        .ignoresSafeArea(.keyboard)
    }
    
    // MARK: - Setup
    
    private func setupInitialState() {
        // Initialize sound cards from DetectedSoundType
        soundCards = DetectedSoundType.allCases.map { type in
            SoundCardData(
                id: UUID(),
                name: type.displayName,
                icon: type.icon,
                accentColor: type.glowColor,
                soundType: type,
                isActive: true // All enabled by default
            )
        }
        
        // Sync with sound manager's enabled types
        updateEnabledSounds()
        
        // Prepare haptic engine
        HapticManager.shared.appDidBecomeActive()
    }
    
    // MARK: - Sound Toggle
    
    private func toggleSound(at index: Int) {
        guard index < soundCards.count else { return }
        soundCards[index].isActive.toggle()
        HapticManager.shared.playImpact(style: .soft)
        updateEnabledSounds()
    }
    
    private func updateEnabledSounds() {
        let enabledTypes = Set(soundCards.filter(\.isActive).map(\.soundType))
        soundManager.enabledSoundTypes = enabledTypes
    }
    
    // MARK: - Listening Control
    
    /// Handles the listening toggle state change
    /// This is where we connect UI actions to manager operations
    private func handleListeningToggle(_ newValue: Bool) {
        Task {
            if newValue {
                // Start listening
                do {
                    try await soundManager.startListening()
                    // Start monitoring Live Activity immediately (MUST be in foreground!)
                    await MainActor.run {
                        liveActivityManager.startMonitoringActivity()
                    }
                } catch {
                    #if DEBUG
                    print("ContentView: Failed to start listening: \(error)")
                    #endif
                }
            } else {
                // Stop listening and end Live Activity
                soundManager.stopListening()
                liveActivityManager.endActivity()
            }
        }
    }
    
    // MARK: - Simulation (Demo Mode)
    
    /// Triggers a simulated sound detection for demos
    /// This bypasses the microphone but uses the same detection pipeline
    private func simulateSound(_ type: DetectedSoundType) {
        // Only allow simulation when listening is active
        guard soundManager.isListening else {
            #if DEBUG
            print("ContentView: Cannot simulate - listening is OFF")
            #endif
            return
        }
        
        #if DEBUG
        print("ContentView: Simulating \(type.displayName)")
        #endif
        
        // Run through the sound manager so the UI reacts normally
        soundManager.simulateSound(type)
    }
}

// MARK: - Type Import Note
// DetectedSoundType properties (icon, glowColor, displayName) are defined in SharedTypes.swift

// MARK: - Preview

#Preview {
    ContentView()
}
