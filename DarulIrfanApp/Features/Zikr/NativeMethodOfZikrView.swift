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
                        FormattedBookPage(page: .init(isContents: false, blocks: [
                            .caption(urdu ? guide.diagramCaptionUr : guide.diagramCaptionEn)
                        ]), scale: readerFontScale)
                    }
                    .padding(DISpacing.lg)
                    .diGlassPanel(cornerRadius: 24)
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
        .diScreenBackground()
        .task(id: attempt) {
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
private struct MethodLatifaDiagram: View {
    private let positions: [(CGFloat, CGFloat)] = [
        (0.70, 0.77), (0.30, 0.77), (0.70, 0.53), (0.30, 0.53),
        (0.50, 0.65), (0.50, 0.24), (0.50, 0.07)
    ]
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Path { path in
                    let w = geometry.size.width, h = geometry.size.height
                    path.move(to: CGPoint(x: w * 0.12, y: h * 0.94))
                    path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.48))
                    path.addQuadCurve(to: CGPoint(x: w * 0.30, y: h * 0.36), control: CGPoint(x: w * 0.12, y: h * 0.36))
                    path.addCurve(to: CGPoint(x: w * 0.70, y: h * 0.36), control1: CGPoint(x: w * 0.30, y: h * 0.10), control2: CGPoint(x: w * 0.70, y: h * 0.10))
                    path.addQuadCurve(to: CGPoint(x: w * 0.88, y: h * 0.48), control: CGPoint(x: w * 0.88, y: h * 0.36))
                    path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.94))
                }.stroke(DIColor.actionForeground.opacity(0.5), lineWidth: 2)
                ForEach(0..<positions.count, id: \.self) { index in
                    Text(verbatim: String(index + 1))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(DIColor.actionForeground)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(DIColor.actionForeground.opacity(0.10)))
                        .position(x: geometry.size.width * positions[index].0,
                                  y: geometry.size.height * positions[index].1)
                }
            }
        }
        .frame(width: 220, height: 220)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Numbered diagram, viewed from the front: 1 lower right, 2 lower left, 3 middle right, 4 middle left, 5 centre, 6 upper centre, 7 at the top."))
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
