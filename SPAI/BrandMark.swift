//
//  BrandMark.swift
//  SPAI
//
//  The SPAI mark — a surgical instrument inside an AI viewfinder on a glass disc.
//
//  • `SterileNodeMark` — the flat mark for small placements (status bar, headers).
//  • `InteractiveLogo` — the real app-icon layers, alive: they float at true depth, spread
//    apart together when you look at them, scan continuously, and when tapped they lock on,
//    sweep, and confirm the instrument as verified.
//

import SwiftUI

// MARK: - Flat mark

/// The composited app icon, used wherever the mark is small.
struct SterileNodeMark: View {
    var size: CGFloat = 38

    var body: some View {
        Image("LogoMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: SPAIColor.primary.opacity(0.35), radius: size * 0.15)
            .accessibilityHidden(true)
    }
}

// MARK: - Interactive logo

/// The app icon, brought to life inside the app.
///
/// • Depth: the brackets and instrument sit physically in front of the disc (`offset(z:)`),
///   so moving your head shows real parallax — like the icon on the Home View.
/// • Gaze: one `HoverEffectGroup` spreads all three layers apart when you look at any of them.
/// • Idle: a scan beam sweeps the viewfinder.
/// • Tap: ripple → brackets lock on → fast sweep → green "verified" check.
struct InteractiveLogo: View {
    var size: CGFloat = 220

    @Namespace private var hoverNamespace
    @State private var floating = false
    @State private var beamDown = false
    @State private var locked = false
    @State private var verified = false
    @State private var scans: [Int] = []
    @State private var scanCount = 0

    var body: some View {
        let group = HoverEffectGroup(hoverNamespace)

        ZStack {
            // Back layer — glass disc with the scan grid.
            Image("LogoBack")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(verified ? SPAIColor.safe : Color.white.opacity(0.2),
                                      lineWidth: verified ? 3 : 1)
                }
                .shadow(color: (verified ? SPAIColor.safe : SPAIColor.primary).opacity(0.4),
                        radius: size * 0.12)
                .hoverEffect(in: group) { effect, isActive, _ in
                    effect.scaleEffect(isActive ? 1.04 : 1.0)
                }

            ForEach(scans, id: \.self) { _ in
                LogoRipple(size: size)
            }

            // Scan beams, clipped to the viewfinder.
            ZStack {
                ScanBeam(width: size * 0.54)
                    .offset(y: beamDown ? size * 0.24 : -size * 0.24)
                    .opacity(verified ? 0 : 0.85)
                ForEach(scans, id: \.self) { _ in
                    LogoSweep(size: size)
                }
            }
            .frame(width: size * 0.6, height: size * 0.6)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.04, style: .continuous))
            .offset(z: size * 0.04)
            .allowsHitTesting(false)

            // Middle layer — viewfinder brackets. They squeeze in to "lock on" when tapped.
            Image("LogoMiddle")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .scaleEffect(locked ? 0.9 : 1.0)
                .offset(z: size * 0.08)
                .hoverEffect(in: group) { effect, isActive, _ in
                    effect.scaleEffect(isActive ? 1.1 : 1.0)
                }

            // Front layer — the instrument.
            Image("LogoFront")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .scaleEffect(locked ? 1.04 : 1.0)
                .offset(z: size * 0.16)
                .hoverEffect(in: group) { effect, isActive, _ in
                    effect.scaleEffect(isActive ? 1.18 : 1.0)
                }

            // Verified badge.
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.1, weight: .heavy))
                .foregroundStyle(SPAIColor.onFill)
                .frame(width: size * 0.24, height: size * 0.24)
                .background(SPAIGradient.success, in: Circle())
                .overlay { Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 2) }
                .shadow(color: SPAIColor.safe.opacity(0.7), radius: 12)
                .scaleEffect(verified ? 1 : 0.3)
                .opacity(verified ? 1 : 0)
                .offset(x: size * 0.35, y: size * 0.35)
                .offset(z: size * 0.22)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .offset(y: floating ? -size * 0.02 : size * 0.02)
        .contentShape(Circle())
        .contentShape(.hoverEffect, Circle())
        .onTapGesture { scan() }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                floating = true
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                beamDown = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel("SPAI logo")
        .accessibilityHint("Tap to run a demo scan")
        .accessibilityAddTraits(.isButton)
    }

    private func scan() {
        scanCount += 1
        let token = scanCount
        scans.append(token)
        verified = false
        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
            locked = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                locked = false
            }
            try? await Task.sleep(for: .milliseconds(450))
            if token == scanCount {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                    verified = true
                }
            }
            try? await Task.sleep(for: .milliseconds(1600))
            scans.removeAll { $0 == token }
            if token == scanCount {
                withAnimation(.easeOut(duration: 0.35)) {
                    verified = false
                }
            }
        }
    }
}

/// A horizontal light bar with a soft halo — the "AI is looking" beam.
struct ScanBeam: View {
    let width: CGFloat
    var color: Color = SPAIColor.primaryBright

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0), color.opacity(0.35), color.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: width, height: width * 0.16)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0), Color.white.opacity(0.95), color.opacity(0)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: width, height: max(2, width * 0.012))
        }
    }
}

/// One fast top-to-bottom sweep, fired on tap.
private struct LogoSweep: View {
    let size: CGFloat
    @State private var done = false

    var body: some View {
        ScanBeam(width: size * 0.58, color: SPAIColor.teal)
            .offset(y: done ? size * 0.3 : -size * 0.3)
            .opacity(done ? 0.2 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7)) {
                    done = true
                }
            }
    }
}

/// Expanding ring fired on tap.
private struct LogoRipple: View {
    let size: CGFloat
    @State private var expanded = false

    var body: some View {
        Circle()
            .strokeBorder(SPAIColor.primaryBright, lineWidth: 3)
            .frame(width: size, height: size)
            .scaleEffect(expanded ? 1.6 : 0.98)
            .opacity(expanded ? 0 : 0.9)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 1.1)) {
                    expanded = true
                }
            }
    }
}

#Preview {
    VStack(spacing: 40) {
        InteractiveLogo(size: 240)
        SterileNodeMark(size: 64)
    }
    .padding(60)
    .background(Color.black)
}
