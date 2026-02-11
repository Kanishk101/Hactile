//
//  PermissionHelpView.swift
//  Hactile
//
//  Permission and Settings guidance view.
//

import SwiftUI
import UIKit

// MARK: - Permission Help View

struct PermissionHelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            PermissionHelpBackground()
            
            VStack(spacing: 24) {
                HStack {
                    Text("Settings & Privacy")
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close settings help")
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    PermissionHelpRow(
                        icon: "mic.fill",
                        title: "Microphone Access",
                        message: "Enable microphone access to detect sounds on-device. Audio is never recorded or stored."
                    )
                    
                    PermissionHelpRow(
                        icon: "bolt.horizontal.circle.fill",
                        title: "Live Activities",
                        message: "Enable notifications to show Live Activities on the Lock Screen and Dynamic Island."
                    )
                    
                    PermissionHelpRow(
                        icon: "lock.shield.fill",
                        title: "Privacy",
                        message: "All analysis runs locally. No internet required."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Button(action: openSettings) {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Open Settings")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    }
                }
                .accessibilityLabel("Open Settings")
                
                Spacer()
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Permission Help Row

struct PermissionHelpRow: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        }
    }
}

// MARK: - Background

struct PermissionHelpBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.15),
                    Color(red: 0.08, green: 0.10, blue: 0.18),
                    Color(red: 0.06, green: 0.07, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            RadialGradient(
                colors: [
                    Color.cyan.opacity(0.12),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    PermissionHelpView()
}
