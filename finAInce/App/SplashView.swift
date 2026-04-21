import SwiftUI

struct SplashView: View {

    // MARK: - Logo animation state

    @State private var showGlow    = false
    @State private var logoOpacity: Double  = 0
    @State private var logoScale:   Double  = 0.85

    // MARK: - Slogan animation state

    @State private var leftOpacity:  Double  = 0
    @State private var leftOffset:   CGFloat = -18
    @State private var rightOpacity: Double  = 0
    @State private var rightOffset:  CGFloat = 18
    @State private var dotScale:     Double  = 0.2
    @State private var dotOpacity:   Double  = 0

    // MARK: - Theme

    /// Matches AccentColor.colorset light mode (violet-600 #7C3AED)
    private let accent = Color(red: 0.486, green: 0.227, blue: 0.929)

    /// Purple gradient mirrors the "AI" glow — brand coherence
    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.55, green: 0.20, blue: 0.95),   // violet
                Color(red: 0.68, green: 0.32, blue: 1.00),   // purple
                Color(red: 0.90, green: 0.40, blue: 0.95)    // magenta accent
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.97, blue: 0.98)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                // ─── Logo ───────────────────────────────────────────────
                HStack(spacing: 0) {
                    Text("fin")
                        .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.18))
                    Text("AI")
                        .foregroundStyle(accentGradient)
                        .shadow(
                            color: accent.opacity(showGlow ? 0.55 : 0),
                            radius: 22
                        )
                    Text("nce")
                        .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.18))
                }
                .font(.system(size: 60, weight: .bold, design: .default))
                .opacity(logoOpacity)
                .scaleEffect(logoScale)

                // ─── Slogan ─────────────────────────────────────────────
                // "A IA é sua. [·] A ferramenta, nossa."
                //  ← slides in from left      slides in from right →
                //  The opposing motion literally performs the meaning:
                //  the user's AI and our tool meeting at the purple dot.
                VStack(spacing: 6) {
                    // Line 1 — "A IA é sua." (user side, primary emphasis)
                    Text(t("splash.sloganLeft"))
                        .font(.system(size: 18, weight: .regular, design: .default))
                        .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.18))
                        .opacity(leftOpacity)
                        .offset(x: leftOffset)

                    // The handshake dot — where the two halves meet
                    Circle()
                        .fill(accentGradient)
                        .frame(width: 5, height: 5)
                        .scaleEffect(dotScale)
                        .opacity(dotOpacity)
                        .shadow(color: accent.opacity(0.45), radius: 4)

                    // Line 2 — "A ferramenta, nossa." (our side, secondary tone)
                    Text(t("splash.sloganRight"))
                        .font(.system(size: 18, weight: .regular, design: .default))
                        .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.18))
                        .opacity(rightOpacity)
                        .offset(x: rightOffset)
                }
            }
        }
        .onAppear(perform: runAnimation)
    }

    // MARK: - Animation timeline

    private func runAnimation() {
        // Phase 1 — Logo: spring fade + scale
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            logoOpacity = 1
            logoScale   = 1
        }

        // Phase 2 — "AI" glow pulse (signals the AI is "coming alive")
        withAnimation(.easeOut(duration: 0.6).delay(0.80)) {
            showGlow = true
        }

        // Phase 3 — "A IA é sua." slides in from the user's side (left)
        withAnimation(.easeOut(duration: 0.45).delay(1.00)) {
            leftOpacity = 1
            leftOffset  = 0
        }

        // Phase 4 — The meeting dot pulses in at center
        withAnimation(.spring(response: 0.40, dampingFraction: 0.58).delay(1.30)) {
            dotScale   = 1
            dotOpacity = 1
        }

        // Phase 5 — "A ferramenta, nossa." slides in from our side (right)
        withAnimation(.easeOut(duration: 0.45).delay(1.50)) {
            rightOpacity = 1
            rightOffset  = 0
        }
    }
}

#Preview {
    SplashView()
}
