import SwiftUI

/// Source images are transcription references, not the reading interface.
struct MethodGuide: Decodable, Sendable {
    struct Section: Decodable, Identifiable, Sendable {
        let id: String
        let kind: String
        let title: String?
        let text: String
        let attribution: String?
    }
    let en: [Section]
    let ur: [Section]
    let diagramCaptionEn: String
    let diagramCaptionUr: String

    static func load() -> MethodGuide? {
        guard let url = SeedBundle.url(forFile: "method_of_zikr"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

struct NativeMethodOfZikrView: View {
    var readerFontScale: Double = 1
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @State private var guide: MethodGuide?
    @State private var isLoading = true
    @State private var attempt = 0
    private var urdu: Bool { locale.language.languageCode?.identifier == "ur" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                SilsilaPageHeader(title: "Method of Zikr")
                ZikrShajraLink()
                if isLoading {
                    ProgressView("Loading")
                        .tint(DIColor.textMuted)
                        .foregroundStyle(DIColor.textMuted)
                        .frame(maxWidth: .infinity).padding(DISpacing.xl)
                } else if let guide {
                    ForEach(urdu ? guide.ur : guide.en) { section in
                        sectionCard(section).diAppear()
                            .accessibilityIdentifier("method-guide-section-" + section.id)
                    }
                    VStack(spacing: DISpacing.md) {
                        MethodLatifaDiagram()
                            .frame(maxWidth: .infinity)
                        FormattedBookPage(page: .init(isContents: false, blocks: [
                            .caption(urdu ? guide.diagramCaptionUr : guide.diagramCaptionEn)
                        ]), scale: readerFontScale)
                    }
                    .padding(DISpacing.lg)
                    .diGlassPanel(cornerRadius: 24)
                    ZikrShajraLink()
                        .accessibilityIdentifier("method-guide-shajra-footer")
                } else {
                    VStack(alignment: .leading, spacing: DISpacing.md) {
                        Text("The Method of Zikr guide could not be loaded. Please try again.")
                            .foregroundStyle(DIColor.textPrimary)
                            .accessibilityIdentifier("method-guide-load-error")
                        Button("Retry") { isLoading = true; attempt += 1 }
                            .buttonStyle(DISecondaryButtonStyle())
                            .accessibilityIdentifier("method-guide-retry")
                    }
                    .padding(DISpacing.lg)
                    .diGlassPanel(cornerRadius: 24)
                }
            }
            .diInterfaceFont(.body)
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .navigationTitle("Method of Zikr")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DIColor.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .diScreenBackground()
        .task(id: attempt) {
            // Returning from Shajra must not replace the reading content with
            // a spinner and collapse the ScrollView's current position.
            guard guide == nil else { return }
            isLoading = true
            #if DEBUG
            // Exercise recovery through real contextual links, without changing bundled files.
            let simulateReadFailure = attempt == 0 && ProcessInfo.processInfo.arguments.contains("--uitesting-method-guide-failure")
            #else
            let simulateReadFailure = false
            #endif
            let loaded = await Task.detached(priority: .userInitiated) {
                QuranQuotation.warmUp()
                return simulateReadFailure ? nil : MethodGuide.load()
            }.value
            guard !Task.isCancelled else { return }
            guide = loaded
            isLoading = false
        }
    }

    private func sectionCard(_ section: MethodGuide.Section) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            if let title = section.title {
                FormattedBookPage(page: .init(isContents: false, blocks: [.heading(title)]), scale: readerFontScale)
                DIJaliDivider(height: 12, opacity: 0.4)
            }
            FormattedBookPage(page: section.kind == "arabic"
                ? .init(isContents: false, blocks: [.arabic(section.text)])
                : BookPageFormatter.articleParagraph(section.text), scale: readerFontScale)
            if let attribution = section.attribution {
                FormattedBookPage(page: .init(isContents: false, blocks: [.caption(attribution)]), scale: readerFontScale)
            }
        }
        .padding(DISpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .diGlassPanel(cornerRadius: 24)
    }
}

/// Position and numbering follow both source diagrams; never mirror anatomy in RTL.
/// Latifa 7 is a circle around the whole body (owner, 2026-11-04), numbered on
/// its top edge; 1-6 keep their places on the body, which is drawn a little
/// smaller inside the circle. A highlighted Latifa (1-7) glows gold.
struct MethodLatifaDiagram: View {
    var highlighted: Int? = nil
    /// The widest the picture grows, circle included; narrower screens shrink it.
    var size: CGFloat = 260
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    /// Latifa 1-6 on the body, in the body's own unit square (unchanged).
    nonisolated static let bodyPositions: [CGPoint] = [
        CGPoint(x: 0.70, y: 0.77), CGPoint(x: 0.30, y: 0.77), CGPoint(x: 0.70, y: 0.53), CGPoint(x: 0.30, y: 0.53),
        CGPoint(x: 0.50, y: 0.65), CGPoint(x: 0.50, y: 0.24)
    ]
    /// The body's outline corners and the top of the head, in the body's unit square.
    nonisolated static let bodyExtremes: [CGPoint] = [
        CGPoint(x: 0.12, y: 0.94), CGPoint(x: 0.88, y: 0.94), CGPoint(x: 0.12, y: 0.48),
        CGPoint(x: 0.88, y: 0.48), CGPoint(x: 0.50, y: 0.165)
    ]
    /// Latifa 7's circle, in the picture's unit square.
    nonisolated static let circleCenter = CGPoint(x: 0.5, y: 0.53)
    nonisolated static let circleRadius: CGFloat = 0.45
    /// The body is drawn at this share of the picture, its (0.5, 0.56) on the circle's centre.
    nonisolated static let bodyScale: CGFloat = 0.78
    private nonisolated static let bodyAnchor = CGPoint(x: 0.5, y: 0.56)

    /// A point of the body's unit square in the picture's unit square.
    nonisolated static func onPicture(_ point: CGPoint) -> CGPoint {
        CGPoint(x: circleCenter.x + (point.x - bodyAnchor.x) * bodyScale,
                y: circleCenter.y + (point.y - bodyAnchor.y) * bodyScale)
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let unit = side / 220
            let at: (CGPoint) -> CGPoint = { point in
                let mapped = Self.onPicture(point)
                return CGPoint(x: mapped.x * side, y: mapped.y * side)
            }
            let sevenLit = highlighted == 7
            ZStack {
                // Latifa 7: the circle around the whole body.
                Circle()
                    .fill(sevenLit ? DIColor.accent.opacity(pulse ? 0.20 : 0.10) : Color.clear)
                    .overlay(Circle().stroke(sevenLit ? DIColor.accent : DIColor.actionForeground.opacity(0.5),
                                             lineWidth: sevenLit ? 3.5 * unit : 2))
                    .frame(width: Self.circleRadius * 2 * side, height: Self.circleRadius * 2 * side)
                    .shadow(color: DIColor.goldGlow.opacity(sevenLit ? (pulse ? 0.95 : 0.55) : 0),
                            radius: sevenLit ? (pulse ? 22 : 12) * unit : 0)
                    .position(x: Self.circleCenter.x * side, y: Self.circleCenter.y * side)
                Path { path in
                    path.move(to: at(CGPoint(x: 0.12, y: 0.94)))
                    path.addLine(to: at(CGPoint(x: 0.12, y: 0.48)))
                    path.addQuadCurve(to: at(CGPoint(x: 0.30, y: 0.36)), control: at(CGPoint(x: 0.12, y: 0.36)))
                    path.addCurve(to: at(CGPoint(x: 0.70, y: 0.36)), control1: at(CGPoint(x: 0.30, y: 0.10)), control2: at(CGPoint(x: 0.70, y: 0.10)))
                    path.addQuadCurve(to: at(CGPoint(x: 0.88, y: 0.48)), control: at(CGPoint(x: 0.88, y: 0.36)))
                    path.addLine(to: at(CGPoint(x: 0.88, y: 0.94)))
                }.stroke(DIColor.actionForeground.opacity(0.5), lineWidth: 2)
                ForEach(0..<Self.bodyPositions.count, id: \.self) { index in
                    badge(index + 1, unit: unit).position(at(Self.bodyPositions[index]))
                }
                // 7's number on the circle's top edge.
                badge(7, unit: unit)
                    .position(x: Self.circleCenter.x * side, y: (Self.circleCenter.y - Self.circleRadius) * side)
            }
            .frame(width: side, height: side)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: size, maxHeight: size)
        .environment(\.layoutDirection, .leftToRight)
        .onAppear { startPulse() }
        .onChange(of: highlighted) { _, _ in startPulse() }
        .onChange(of: reduceMotion) { _, _ in startPulse() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Numbered diagram, viewed from the front: 1 lower right, 2 lower left, 3 middle right, 4 middle left, 5 centre, 6 upper centre, 7 a circle around the whole body."))
    }

    private func badge(_ number: Int, unit: CGFloat) -> some View {
        let lit = highlighted == number
        return Text(verbatim: String(number))
            .font(.system(size: 16 * unit, weight: .bold, design: .rounded))
            .foregroundStyle(lit ? DIColor.background : DIColor.actionForeground)
            .frame(width: 30 * unit, height: 30 * unit)
            // 7's badge sits on the circle's line, so it is never see-through.
            .background {
                ZStack {
                    if number == 7 && !lit { Circle().fill(DIColor.background) }
                    Circle().fill(lit ? DIColor.accent : DIColor.actionForeground.opacity(0.10))
                }
            }
            .scaleEffect(lit ? 1.35 : 1)
            .diGoldGlow(radius: lit ? 14 : 0, opacity: lit ? 0.8 : 0)
    }

    /// The gold circle breathes while 7 is highlighted; still under Reduce Motion.
    private func startPulse() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { pulse = false }
        guard highlighted == 7, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
    }
}

private struct MethodGuideReaderScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1
}
extension EnvironmentValues {
    var methodGuideReaderScale: Double {
        get { self[MethodGuideReaderScaleKey.self] }
        set { self[MethodGuideReaderScaleKey.self] = newValue }
    }
}

/// Contextual access to the same verified native guide from any activity.
struct MethodOfZikrLink: View {
    var compact = false
    @Environment(\.methodGuideReaderScale) private var readerScale
    var body: some View {
        Group {
            if compact {
                NavigationLink {
                    NativeMethodOfZikrView(readerFontScale: readerScale)
                } label: {
                    Label("Method of Zikr", systemImage: "book.pages")
                        .diInterfaceFont(.subheadline, weight: .semibold)
                        .foregroundStyle(DIColor.actionForeground)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(LinearGradient(colors: [DIColor.surface, DIColor.sandstone], startPoint: .top, endPoint: .bottom), in: Capsule())
                        .overlay(Capsule().strokeBorder(DIColor.accent.opacity(0.45)))
                }.buttonStyle(DIPressableStyle())
            } else {
                NavigationLink {
                    NativeMethodOfZikrView(readerFontScale: readerScale)
                } label: {
                    Label("Method of Zikr", systemImage: "book.pages")
                }.buttonStyle(DISecondaryButtonStyle())
            }
        }
        .accessibilityIdentifier("method-of-zikr-shortcut")
    }
}
