//
//  StatusBarPanel.swift
//  SPAI
//
//  Created by Juan Adams on 6/7/26.
//


//
//  StatusBarPanel.swift
//  SPAI
//
//  The top HUD status bar: identity, session time, role, and session
//  controls. Anchors the immersive workspace and sets the visual tone.
//  Mirrors the Figma layout using the app's existing design tokens.
//

import SwiftUI
internal import Combine

struct StatusBarPanel: View {
    // Session timer state. Counts up while the workflow is active.
    @State private var sessionSeconds: Int = 0
    @State private var isPaused = false
    @Environment(AppModel.self) private var appModel

    // Drives the session timer once per second.
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: SPAISpacing.l) {
            identityBlock

            divider

            sessionTimeBlock

            divider

            roleBlock

            Spacer()

            controlButtons
        }
        .padding(.horizontal, SPAISpacing.l)
        .padding(.vertical, SPAISpacing.m)
        .frame(width: 900)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SPAIRadius.large))
        .ledBorder(cornerRadius: SPAIRadius.large, lineWidth: 1.5)
        .onReceive(timer) { _ in
            // Only advance the clock when the session isn't paused.
            if !isPaused { sessionSeconds += 1 }
        }
    }

    // MARK: - Left: identity

    private var identityBlock: some View {
        HStack(spacing: SPAISpacing.s + 4) {
            // Initials badge.
            Text("SP")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(SPAIColor.primary.opacity(0.35), in: RoundedRectangle(cornerRadius: SPAIRadius.small))

            VStack(alignment: .leading, spacing: 2) {
                Text("SPAI")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("SPD — OR Suite 3")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Center-left: session time

    private var sessionTimeBlock: some View {
        HStack(spacing: 8) {
            Text("SESSION TIME")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Text(formattedTime)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, SPAISpacing.m)
        .padding(.vertical, SPAISpacing.s)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
    }

    // MARK: - Center: role

    private var roleBlock: some View {
            Menu {
                // Each role is a selectable menu item that updates AppModel.
                ForEach(TechRole.allCases) { role in
                    Button {
                        appModel.role = role
                    } label: {
                        if appModel.role == role {
                            Label(role.rawValue, systemImage: "checkmark")
                        } else {
                            Text(role.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(SPAIColor.accent)
                        .frame(width: 8, height: 8)
                    Text(appModel.role.rawValue)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .buttonStyle(.plain)
        }

    // MARK: - Right: controls

    private var controlButtons: some View {
        HStack(spacing: SPAISpacing.s + 4) {
            Button {
                isPaused.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    Text(isPaused ? "Resume" : "Pause")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, SPAISpacing.m)
                .padding(.vertical, SPAISpacing.s + 2)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)

            Button {
                // Export hook — wired to the backend/report export later.
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Export")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, SPAISpacing.m)
                .padding(.vertical, SPAISpacing.s + 2)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: SPAIRadius.small))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 36)
    }

    /// Turns the running second count into MM:SS.
    private var formattedTime: String {
        let minutes = sessionSeconds / 60
        let seconds = sessionSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    StatusBarPanel()
        .environment(AppModel())
        .padding(60)
        .background(.black)
}
