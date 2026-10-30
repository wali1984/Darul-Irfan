import SwiftUI

/// A book's cover, made in the Silsila's style (boards/Book.dc.html): an
/// emerald binding with a dark spine, a gold frame, the seal at the head, the
/// title in the Urdu face (or as written), and the author at the foot. It
/// floats gently in a breathing gold light, and a slow octagram turns in the
/// binding. Reduce Motion keeps it still.
struct BookCoverView: View {
    let item: ContentItem
    var width: CGFloat = 210

    @State private var floating = false
    @State private var breathing = false
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var height: CGFloat { width * 300 / 210 }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [DIColor.goldGlow.opacity(0.40), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: width * 0.72
                    )
                )
                .frame(width: width * 1.43, height: width * 1.43)
                .scaleEffect(breathing ? 1.08 : 1)
                .opacity(breathing ? 1 : 0.55)
                .accessibilityHidden(true)
            cover
                .rotationEffect(.degrees(-2))
                .offset(y: floating ? -6 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height + 30)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                floating = true
            }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                breathing = true
            }
            withAnimation(.linear(duration: 120).repeatForever(autoreverses: false)) {
                turning = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cover of \(item.title)"))
    }

    private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ZStack(alignment: .top) {
            shape.fill(
                LinearGradient(
                    colors: [Color(hex: 0x0E8A60), Color(hex: 0x0B7250), Color(hex: 0x04321F)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            // The spine.
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(hex: 0x032619))
                    .frame(width: 6)
                Spacer(minLength: 0)
            }
            DIOctagram(innerRatio: 0.5)
                .stroke(Color(hex: 0xFBCE54), lineWidth: 1.6)
                .frame(width: width * 1.24, height: width * 1.24)
                .opacity(0.16)
                .rotationEffect(.degrees(turning ? 360 : 0))
                .offset(y: height * 0.40)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color(hex: 0xE0B75F).opacity(0.75), lineWidth: 1.5)
                .padding(12)
            VStack(spacing: 0) {
                seal
                    .padding(.top, 34)
                titleText
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                Spacer(minLength: 0)
                if let author = item.author, !author.isEmpty {
                    authorText(author)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 30)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.stroke(Color(hex: 0xE0B75F).opacity(0.5), lineWidth: 1))
        .readSheen(cornerRadius: 14, period: 8, strength: 0.16)
        .shadow(color: Color(hex: 0x064B34).opacity(0.45), radius: 25, y: 24)
    }

    /// The seal on its white plate with a gold edge.
    private var seal: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 60, height: 60)
                .overlay(Circle().stroke(Color(hex: 0xE0B75F).opacity(0.9), lineWidth: 1.5))
                .shadow(color: DIColor.goldGlow.opacity(0.5), radius: 10)
            DISealEmblem(diameter: 54, glow: false)
        }
    }

    @ViewBuilder
    private var titleText: some View {
        if let urdu = item.titleUrdu, !urdu.isEmpty {
            Text(verbatim: urdu)
                .font(DIFont.urduBody(scale: 1.3))
                .foregroundStyle(Color(hex: 0xFFE9A8))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .diGoldGlow(radius: 10, opacity: 0.55)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            Text(verbatim: item.title)
                .font(.system(.title3, design: .serif).weight(.bold))
                .foregroundStyle(Color(hex: 0xFFE9A8))
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .minimumScaleFactor(0.6)
                .diGoldGlow(radius: 10, opacity: 0.55)
        }
    }

    /// The author in small capitals; Urdu has no capitals and no letter spacing.
    private func authorText(_ author: String) -> some View {
        let isLatin = !ScriptDirection.isRightToLeft(author, fallbackLanguage: nil)
        return Text(verbatim: author)
            .font(.system(size: 10, weight: .heavy))
            .tracking(isLatin ? 1.6 : 0)
            .textCase(isLatin ? .uppercase : nil)
            .foregroundStyle(Color(hex: 0xFFE9A8).opacity(0.85))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }
}
