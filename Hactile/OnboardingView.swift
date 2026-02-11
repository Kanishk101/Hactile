//
//  OnboardingView.swift
//  Hactile
//
//  First-run onboarding experience for Hactile.
//
//  ## Design Philosophy
//  This flow prioritizes trust and clarity over feature promotion.
//  Users should understand exactly what Hactile does and doesn't do
//  before granting any permissions.
//
//  ## Permission Philosophy
//  We request permissions but NEVER block app entry if denied.
//  Users can always change permissions later in Settings.
//  This respects user autonomy and avoids frustrating loops.
//

import SwiftUI
import AVFoundation
import UserNotifications

// MARK: - Onboarding 'View

struct OnboardingView: View {
    
    // MARK: - Persistence
    
    /// Tracks whether onboarding has been completed
    /// Using AppStorage for automatic persistence across launches
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    
    // MARK: - Local State
    
    @State private var currentPage: Int = 0
    @State private var microphoneRequested: Bool = false
    @State private var notificationsRequested: Bool = false
    @State private var microphoneGranted: Bool = false
    @State private var notificationsGranted: Bool = false
    
    // MARK: - Computed Properties
    
    /// Both permissions have been requested (regardless of result)
    private var permissionsComplete: Bool {
        microphoneRequested && notificationsRequested
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Animated background (consistent with Dashboard)
            OnboardingBackground()
            
            // Paged content
            TabView(selection: $currentPage) {
                ConceptPage()
                    .tag(0)
                
                PrivacyPage()
                    .tag(1)
                
                SetupPage(
                    microphoneRequested: $microphoneRequested,
                    notificationsRequested: $notificationsRequested,
                    microphoneGranted: $microphoneGranted,
                    notificationsGranted: $notificationsGranted
                )
                .tag(2)
                
                SiriAnnouncePage(
                    permissionsComplete: permissionsComplete,
                    onComplete: completeOnboarding
                )
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Actions
    
    private func completeOnboarding() {
        // Mark onboarding as complete
        // This will cause HactileApp to show ContentView
        hasCompletedOnboarding = true
    }
}

// MARK: - Onboarding Background

/// Animated gradient background consistent with the main Dashboard
struct OnboardingBackground: View {
    @State private var animationPhase: CGFloat = 0
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let phase = CGFloat(now.truncatingRemainder(dividingBy: 20)) / 20
                
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
                let orbs: [(CGFloat, CGFloat, Color, CGFloat)] = [
                    (0.3, 0.25, Color(red: 0.15, green: 0.25, blue: 0.45), 0.5),
                    (0.7, 0.35, Color(red: 0.2, green: 0.15, blue: 0.4), 0.4),
                    (0.5, 0.75, Color(red: 0.12, green: 0.2, blue: 0.42), 0.55)
                ]
                
                for (index, orb) in orbs.enumerated() {
                    let offset = CGFloat(index) * 0.33
                    let breathe = 1.0 + sin((phase + offset) * .pi * 2) * 0.1
                    let xShift = sin((phase + offset) * .pi * 2) * 20
                    let yShift = cos((phase + offset) * .pi * 2) * 15
                    
                    let cx = orb.0 * size.width + xShift
                    let cy = orb.1 * size.height + yShift
                    let r = size.width * orb.3 * breathe
                    
                    let orbGradient = Gradient(colors: [
                        orb.2.opacity(0.5),
                        orb.2.opacity(0.0)
                    ])
                    
                    context.fill(
                        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                        with: .radialGradient(orbGradient, center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r)
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Page 1: The Concept

struct ConceptPage: View {
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: CGFloat = 0.8
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Hero icon with pulse animation
            ZStack {
                // Outer pulse rings
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseScale + CGFloat(index) * 0.3)
                        .opacity(pulseOpacity - Double(index) * 0.25)
                }
                
                // Glow backdrop
                Circle()
                    .fill(Color.cyan.opacity(0.15))
                    .frame(width: 140, height: 140)
                    .blur(radius: 30)
                
                // Icon
                Image(systemName: "waveform")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .cyan.opacity(0.5), radius: 20)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    pulseScale = 1.4
                    pulseOpacity = 0.3
                }
            }
            
            // Title
            VStack(spacing: 16) {
                Text("Awareness")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("You Can Feel.")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            
            // Subtitle
            Text("Sound recognition through haptics")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Page 2: The Privacy

struct PrivacyPage: View {
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Shield icon
            ZStack {
                // Glow
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 140, height: 140)
                    .blur(radius: 30)
                
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .green.opacity(0.5), radius: 20)
            }
            
            // Title
            VStack(spacing: 16) {
                Text("Listening,")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Not Recording.")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            
            // Privacy points
            VStack(alignment: .leading, spacing: 20) {
                PrivacyPoint(
                    icon: "cpu",
                    text: "Audio is processed entirely on-device"
                )
                
                PrivacyPoint(
                    icon: "xmark.circle",
                    text: "Nothing is recorded or stored"
                )
                
                PrivacyPoint(
                    icon: "wifi.slash",
                    text: "No internet connection required"
                )
            }
            .padding(.top, 20)
            
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

struct PrivacyPoint: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: 32)
            
            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Page 3: The Setup

struct SetupPage: View {
    @Binding var microphoneRequested: Bool
    @Binding var notificationsRequested: Bool
    @Binding var microphoneGranted: Bool
    @Binding var notificationsGranted: Bool
    
    private var canProceed: Bool {
        microphoneRequested && notificationsRequested
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 140, height: 140)
                    .blur(radius: 30)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .purple.opacity(0.5), radius: 20)
            }
            
            // Title
            VStack(spacing: 16) {
                Text("Let's Get")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Started.")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            
            // Permission buttons
            VStack(spacing: 16) {
                // Microphone permission
                PermissionButton(
                    title: "Enable Microphone",
                    icon: "mic.fill",
                    isRequested: microphoneRequested,
                    isGranted: microphoneGranted,
                    accentColor: .cyan
                ) {
                    requestMicrophonePermission()
                }
                
                // Notifications permission (required for Live Activities)
                PermissionButton(
                    title: "Enable Live Activities",
                    icon: "bell.badge.fill",
                    isRequested: notificationsRequested,
                    isGranted: notificationsGranted,
                    accentColor: .orange
                ) {
                    requestNotificationPermission()
                }
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding(.horizontal, 32)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: canProceed)
    }
    
    // MARK: - Permission Requests
    
    /// Requests microphone permission using AVAudioApplication (iOS 17+)
    private func requestMicrophonePermission() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                microphoneRequested = true
                microphoneGranted = granted
            }
        }
    }
    
    /// Requests notification permission (required for Live Activities)
    /// Live Activities require notification authorization to display on Lock Screen
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive]) { granted, _ in
            DispatchQueue.main.async {
                notificationsRequested = true
                notificationsGranted = granted
            }
        }
    }
}

// MARK: - Page 4: Siri Announce Notifications

struct SiriAnnouncePage: View {
    let permissionsComplete: Bool
    var onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.15))
                    .frame(width: 140, height: 140)
                    .blur(radius: 30)
                
                Image(systemName: "waveform.and.person.filled")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.indigo, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .indigo.opacity(0.5), radius: 20)
            }
            
            // Title
            VStack(spacing: 16) {
                Text("Siri Can")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Announce Alerts.")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.indigo, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            
            // Explanation
            Text("When wearing AirPods, Siri can read your Hactile alerts aloud — perfect for hands-free awareness.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            
            // Open Settings button
            Button {
                if let url = URL(string: "App-prefs:SIRI&path=ANNOUNCE_NOTIFICATIONS") {
                    UIApplication.shared.open(url)
                } else if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gear")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("Open Siri Settings")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.indigo.opacity(0.4), lineWidth: 1)
                }
            }
            
            // Enter Hactile button
            Button(action: onComplete) {
                HStack(spacing: 12) {
                    Text("Enter Hactile")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.purple, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .shadow(color: .purple.opacity(0.4), radius: 20, y: 10)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Permission Button

struct PermissionButton: View {
    let title: String
    let icon: String
    let isRequested: Bool
    let isGranted: Bool
    let accentColor: Color
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: statusIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                
                // Label
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text(statusText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Chevron or checkmark
                Image(systemName: isRequested ? (isGranted ? "checkmark.circle.fill" : "xmark.circle.fill") : "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isRequested ? (isGranted ? .green : .orange) : .secondary)
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            }
        }
        .disabled(isRequested)
        .opacity(isRequested ? 0.8 : 1.0)
    }
    
    private var statusIcon: String {
        if isRequested {
            return isGranted ? "checkmark" : icon
        }
        return icon
    }
    
    private var statusColor: Color {
        if isRequested {
            return isGranted ? .green : .orange
        }
        return accentColor
    }
    
    private var statusText: String {
        if isRequested {
            return isGranted ? "Enabled" : "Denied — can enable in Settings"
        }
        return "Tap to enable"
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
