import SwiftUI
import AuthenticationServices

struct WelcomeView: View {
    let session: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var appeared = false
    private let cream = Color(red: 0.98, green: 0.96, blue: 0.92)
    private let ink = Color(red: 0.22, green: 0.13, blue: 0.09)

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 650 || dynamicTypeSize.isAccessibilitySize
            let artworkWidth = min(geometry.size.width * 0.72, compact ? 210 : 270)
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkle").foregroundStyle(.orange)
                    Text("FRENCH FRIED").tracking(2.2)
                }
                .font(.caption.weight(.heavy))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                Spacer(minLength: 8)
                if !dynamicTypeSize.isAccessibilitySize {
                    OnboardingPotato()
                        .frame(width: artworkWidth, height: artworkWidth * 1163 / 1352)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared || reduceMotion ? 0 : 14)
                }
                Spacer(minLength: 8)
                VStack(spacing: compact ? 8 : 12) {
                    Text("From couch to crispy.")
                        .font(.system(size: compact ? 34 : 42, weight: .heavy, design: .rounded))
                        .tracking(-1).multilineTextAlignment(.center)
                        .minimumScaleFactor(0.75).foregroundStyle(ink)
                    Text("A little running. A lot of heart.")
                        .font(.headline.weight(.medium)).multilineTextAlignment(.center)
                        .foregroundStyle(ink.opacity(0.68))
                    Text("Build a running habit with walk–run sessions, saved progress, and an optional crew.")
                        .font(.subheadline).multilineTextAlignment(.center)
                        .foregroundStyle(ink.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                VStack(spacing: 10) {
                    SignInWithAppleButton(.continue, onRequest: { session.configure($0) }, onCompletion: { result in
                        Task { await session.complete(result) }
                    })
                    .signInWithAppleButtonStyle(.black).frame(height: 56)
                    .disabled(session.signingIn)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    if let error = session.error {
                        Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    } else {
                        Label("Your routes stay private", systemImage: "lock.fill")
                            .font(.footnote).foregroundStyle(ink.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 26).padding(.vertical, compact ? 12 : 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cream.ignoresSafeArea())
            .onAppear {
                withAnimation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.9)) { appeared = true }
            }
        }
    }
}


/// Reuses the approved cutout; motion stops when accessibility requests it.
struct OnboardingPotato: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var animates: Bool { !reduceMotion && scenePhase == .active }

    var body: some View {
        Image("WelcomePotato")
            .resizable().scaledToFit()
            .phaseAnimator(animates ? [false, true] : [false]) { content, raised in
                content
                    .offset(y: raised ? -6 : 0)
                    .rotationEffect(.degrees(animates ? (raised ? 1.2 : -1.2) : 0))
                    .scaleEffect(raised ? 1.015 : 1)
            } animation: { _ in .easeInOut(duration: 2.6) }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkle")
                    .font(.system(size: 19, weight: .medium)).foregroundStyle(.orange.opacity(0.65))
                    .phaseAnimator(animates ? [false, true] : [false]) { content, glowing in
                        content.opacity(glowing ? 0.9 : 0.3).scaleEffect(glowing ? 1 : 0.75)
                    } animation: { _ in .easeInOut(duration: 1.8) }
                    .padding(.trailing, 8).padding(.top, 18)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("A sleepy potato relaxing on a couch")
    }
}
