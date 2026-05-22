import SwiftUI

struct BookAIStep: View {

    @Binding var enableAI: Bool
    let onConfirm: () -> Void

    // Drives the animated MeshGradient middle-point
    @State private var gradientPhase = false

    // MARK: - Body

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                bookVisual
                    .frame(height: 180)

                Spacer().frame(height: 44)

                textBlock

                Spacer().frame(height: 52)

                AITogglePill(isOn: $enableAI)

                Spacer()

                confirmButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        // Base: always-present deep navy
        LinearGradient(
            colors: [Color(hex: "0F172A"), Color(hex: "1E293B")],
            startPoint: .top,
            endPoint: .bottom
        )

        // AI gradient: fades in when enabled
        if enableAI {
            if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        .init(0, 0), .init(0.5, 0), .init(1, 0),
                        .init(0, 0.5),
                        .init(gradientPhase ? 0.2 : 0.8, gradientPhase ? 0.7 : 0.3),
                        .init(1, 0.5),
                        .init(0, 1), .init(0.5, 1), .init(1, 1)
                    ],
                    colors: [
                        .indigo, Color(hex: "7C3AED"), Color(hex: "1D4ED8"),
                        Color(hex: "7C3AED"), Color(hex: "4338CA"), .indigo,
                        Color(hex: "1D4ED8"), .indigo, Color(hex: "7C3AED")
                    ]
                )
                .onAppear {
                    gradientPhase = false
                    withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                        gradientPhase = true
                    }
                }
            } else {
                LinearGradient(
                    colors: [Color(hex: "1E1B4B"), Color(hex: "312E81"), Color(hex: "1E1B4B")],
                    startPoint: gradientPhase ? .topLeading : .bottomTrailing,
                    endPoint: gradientPhase ? .bottomTrailing : .topLeading
                )
                .onAppear {
                    gradientPhase = false
                    withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: true)) {
                        gradientPhase = true
                    }
                }
            }
        }
    }

    // MARK: - Book visual + sparkles

    private var bookVisual: some View {
        AICompanionIllustration(isOn: enableAI)
    }

    // MARK: - Text block

    private var textBlock: some View {
        VStack(spacing: 12) {
            Text("AI Companion")
                .font(.system(size: 40, weight: .regular, design: .serif))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Ask questions about characters, plot,\nand themes — without spoilers.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.70))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }

    // MARK: - Confirm button

    private var confirmButton: some View {
        Button(action: onConfirm) {
            Text("Add to Library")
                .font(.body.weight(.semibold))
                .foregroundStyle(enableAI ? Color(hex: "0F172A") : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(enableAI ? Color.white : Color.white.opacity(0.18))
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: enableAI)
    }
}

// MARK: - Custom pill toggle

private struct AITogglePill: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack {
            // Track
            Capsule()
                .fill(.white.opacity(0.10))
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
                .frame(width: 280, height: 64)

            // Sliding selection indicator
            HStack(spacing: 0) {
                if isOn { Spacer(minLength: 0) }
                Capsule()
                    .fill(.white.opacity(0.20))
                    .frame(width: 134, height: 52)
                if !isOn { Spacer(minLength: 0) }
            }
            .frame(width: 268)

            // Labels
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 15))
                    Text("Off")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundStyle(isOn ? .white.opacity(0.30) : .white)
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15))
                    Text("On")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundStyle(isOn ? .white : .white.opacity(0.30))
                .frame(maxWidth: .infinity)
            }
            .frame(width: 280)
            .animation(.easeInOut(duration: 0.2), value: isOn)
        }
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isOn.toggle()
            }
        }
    }
}

// MARK: - AI Companion Illustration

private struct AICompanionIllustration: View {
    var isOn: Bool

    // Pre-calculate gradients outside the TimelineView to avoid recreating structs every frame
    private let bookGradientOn = LinearGradient(
        colors: [.white, Color(hex: "E0E7FF")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    private let bookGradientOverlay = LinearGradient(
        colors: [.white.opacity(0.8), .clear],
        startPoint: .top,
        endPoint: .bottom
    )
    
    private let bookGradientOff = LinearGradient(
        colors: [Color(hex: "64748B"), Color(hex: "334155")],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        // Pausing the timeline entirely when OFF stops all CPU/GPU updates
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isOn)) { ctx in
            // When paused, phase stays constant
            let phase = isOn ? ctx.date.timeIntervalSinceReferenceDate : 0

            ZStack {
                // --- 1. Distributed Ambient Glow ---
                if isOn {
                    ZStack {
                        // Cyan Glow (Restored blur for soft edges)
                        Circle()
                            .fill(Color(hex: "38BDF8").opacity(0.8))
                            .frame(width: 100, height: 100)
                            .blur(radius: 30)
                            .offset(x: -50 + 5 * cos(phase * 0.3), y: -30 + 5 * sin(phase * 0.2))
                            
                        // Pink Glow
                        Circle()
                            .fill(Color(hex: "F472B6").opacity(0.8))
                            .frame(width: 100, height: 100)
                            .blur(radius: 30)
                            .offset(x: 50 + 5 * sin(phase * 0.25), y: 30 + 5 * cos(phase * 0.3))

                        // Purple Core
                        Circle()
                            .fill(Color(hex: "C084FC").opacity(0.9))
                            .frame(width: 120, height: 120)
                            .blur(radius: 35)
                            .offset(x: 5 * cos(phase * 0.5), y: 5 * sin(phase * 0.5))
                            .scaleEffect(1.0 + 0.05 * sin(phase * 0.6))
                    }
                    .blendMode(.screen)
                    // Removed drawingGroup() here to fix clipping issues (the square box)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }

                // --- 2. Main Scene (Book + 2D Orbiting Sparkles) ---
                ZStack {
                    // The Book
                    ZStack {
                        if isOn {
                            // Iridescent Glass Book
                            Image(systemName: "book.fill")
                                .font(.system(size: 84))
                                .foregroundStyle(bookGradientOn)
                                .overlay(
                                    Image(systemName: "book.fill")
                                        .font(.system(size: 84))
                                        .foregroundStyle(bookGradientOverlay)
                                        .blendMode(.overlay)
                                )
                                // Shadow rendered before offset for efficient caching
                                .shadow(color: Color(hex: "A78BFA").opacity(0.4), radius: 15, x: 0, y: 5)
                                .offset(y: 15 + 1 * sin(phase * 1.5))
                        } else {
                            // Sleeping Dark Book
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 84))
                                .foregroundStyle(bookGradientOff)
                                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                                .offset(y: 15)
                        }
                    }
                    .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isOn)

                    // 2D Orbiting Sparkles (Optimized)
                    if isOn {
                        ZStack { // Replaced Group with ZStack
                            ForEach(0..<12, id: \.self) { i in
                                let isRing1 = i < 6
                                let offsetIndex = Double(i % 6)
                                
                                let orbitPhase = isRing1 
                                    ? phase * 0.4 + (offsetIndex / 6.0) * .pi * 2
                                    : -(phase * 0.25) + (offsetIndex / 6.0) * .pi * 2
                                    
                                let xRadius = isRing1 ? 65.0 : 80.0
                                let yRadius = isRing1 ? 50.0 : 60.0
                                
                                let xOffset = xRadius * cos(orbitPhase)
                                let yOffset = yRadius * sin(orbitPhase) + 15 // Center on book
                                
                                Image(systemName: "sparkle")
                                    .font(.system(size: (isRing1 ? 10 : 6) + CGFloat(i % 3) * 3))
                                    .foregroundStyle(.white)
                                    // Removed expensive live shadow on moving elements
                                    .offset(x: xOffset, y: yOffset)
                                    .opacity(0.4 + 0.3 * sin(orbitPhase * 2.0))
                            }
                        }
                        // Removed drawingGroup() here to ensure SF Symbols render properly
                        .transition(.opacity)
                    }
                }

                // --- 3. OFF State Zzz ---
                if !isOn {
                    Image(systemName: "zzz")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(hex: "64748B"))
                        .offset(x: 50, y: -40)
                        .transition(.opacity.combined(with: .scale(scale: 0.5)))
                }
            }
            .frame(height: 180)
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var aiEnabled = false
    NavigationStack {
        BookAIStep(enableAI: $aiEnabled) {}
    }
}
