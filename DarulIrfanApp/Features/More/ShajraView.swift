import SwiftUI

// The Shajra, recreated in the app's own theme (owner, 30 October 2026:
// "Recreate shajra image using our theme and keeping logo in it ... the
// english urdu text needs to be animated in shajrah"). It replaces the
// library's page, a list and the website's small chart, wherever that page
// was reached.
//
// Top to bottom: an emerald header with the Silsila's seal and the titles;
// the chain of 13, from the Holy Prophet ﷺ to the present Sheikh, each a
// node on a gold trunk beside a card with the Urdu line over the English
// one; and the closing dua. On first appearance the trunk draws downward
// and the rows arrive in turn; while on screen a band of gold light passes
// over each Urdu line and a small light travels down the trunk. Reduce
// Motion shows all of it at once, still. The words are in ShajraText.

// MARK: - Routing

/// Where the Shajra opens from: the Halqah tab's Shajra row, and the
/// library's Shajra page wherever that is reached (search, topics, Saved,
/// a shelf).
enum ShajraRoute {
    /// The library's Shajra page (category `.shajra`).
    static let libraryItemID = "page-shajra-silsila-naqshbandia-owaisiah"

    /// True for the library page that opens `ShajraView` instead of itself.
    static func opensShajraView(itemID: String) -> Bool {
        itemID == libraryItemID
    }
}

// MARK: - Motion

/// The Shajra's timings, in seconds. Calm and slow: nothing jumps.
enum ShajraMotion {
    /// The gold trunk draws downward over `trunkDuration`, after `trunkDelay`.
    static let trunkDelay = 0.25
    static let trunkDuration = 2.6
    /// The first row arrives after `firstRowDelay`, each next one
    /// `rowStagger` later.
    static let firstRowDelay = 0.35
    static let rowStagger = 0.14
    /// A row's Urdu line rises and fades in over `lineDuration`, `urduLag`
    /// after its badge; its English follows `englishLag` after the Urdu.
    static let lineDuration = 0.45
    static let urduLag = 0.05
    static let englishLag = 0.15
    /// The closing dua rises in once the chain has arrived.
    static let closingDelay = 2.3
    /// When the band of gold light first passes over the header's title and
    /// over the closing dua.
    static let headerShimmerDelay = 0.9
    static let closingShimmerDelay = 3.2
    /// The light on the trunk: one pass of `lightTravel` every
    /// `lightPeriod`, from `lightStart`, once the trunk has drawn.
    static let lightStart = trunkDelay + trunkDuration + 0.4
    static let lightPeriod = 6.0
    static let lightTravel = 3.2

    /// When row `index` arrives, after the page appears.
    static func rowDelay(_ index: Int) -> Double {
        firstRowDelay + Double(index) * rowStagger
    }

    /// When the band of gold light first passes over row `index`'s Urdu
    /// line: half a second after the row above, so the lines never move in
    /// step.
    static func shimmerDelay(_ index: Int) -> Double {
        1.5 + Double(index) * 0.5
    }

    /// The light on the trunk `elapsed` seconds after the page appeared: how
    /// far down it is (0 at the first node, 1 at the last) and how bright
    /// (dark between passes, fading in at the head and out at the foot).
    static func trunkLight(elapsed: Double) -> (position: Double, brightness: Double) {
        guard elapsed >= lightStart else { return (0, 0) }
        let time = (elapsed - lightStart).truncatingRemainder(dividingBy: lightPeriod)
        guard time < lightTravel else { return (1, 0) }
        let progress = time / lightTravel
        let eased = progress * progress * (3 - 2 * progress)
        let brightness = min(1, progress / 0.12, (1 - progress) / 0.12)
        return (eased, brightness)
    }
}

// MARK: - Colours

/// The Shajra's colours that the shared tokens do not carry.
enum ShajraPalette {
    /// Emerald ink on gold.
    static let emeraldInk = Color(hex: 0x064B34)
    /// Gold text on emerald, #FFE3A0, for 4.5:1.
    static let goldOnEmerald = Color(hex: 0xFFE3A0)
    /// The Holy Prophet's card: gold, #FFE9A8 to #E0B75F.
    static let prophetCard = LinearGradient(
        colors: [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    /// The trunk: pale gold at the head of the chain, deep gold at its foot.
    static let trunk = LinearGradient(
        colors: [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F), Color(hex: 0xC6A253), Color(hex: 0xB48A2C)],
        startPoint: .top,
        endPoint: .bottom
    )
    /// The small light that travels down the trunk.
    static let light = Color(hex: 0xFFF4CF)
}

// MARK: - The page

/// The Shajra of Silsila Naqshbandia Owaisiah, drawn in the app's theme.
@MainActor
struct ShajraView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DISpacing.lg) {
                ShajraHeader()
                ShajraChain()
                ShajraClosingDua()
            }
            .padding(DISpacing.md)
            .padding(.bottom, DISpacing.md)
            .diResponsiveWidth()
        }
        .background {
            ShajraPageDecor()
                .ignoresSafeArea()
        }
        .diScreenBackground()
        .navigationTitle("Shajra")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The page's light: a soft gold glow from the top, and a large octagram
/// turning very slowly behind the chain. It stays put while the page
/// scrolls.
private struct ShajraPageDecor: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [HalqahInk.pageGlow, Color.clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: max(geo.size.width, 1) * 0.9
                )
                .frame(width: geo.size.width, height: 360)
                .position(x: geo.size.width / 2, y: 180)
                ShajraTurningOctagram()
                    .frame(width: 560, height: 560)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.56)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The octagram watermark, turning very slowly; still under Reduce Motion.
private struct ShajraTurningOctagram: View {
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DIOctagram(innerRatio: 0.5)
            .stroke(DIColor.accent, lineWidth: 1.6)
            .opacity(0.12)
            .rotationEffect(.degrees(turning ? 360 : 0))
            // SwiftUI turns a rotation the other way in a right-to-left
            // layout; the star turns the same way in Urdu.
            .environment(\.layoutDirection, .leftToRight)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 240).repeatForever(autoreverses: false)) {
                    turning = true
                }
            }
    }
}

// MARK: - Header

/// The emerald header: the Silsila's seal with its breathing gold halo, the
/// Urdu title in gold with light passing over it, the Silsila's name, and
/// the English title in small capitals. VoiceOver reads it as a heading.
private struct ShajraHeader: View {
    var body: some View {
        VStack(spacing: 8) {
            DILivingSealMark(diameter: 84)
                .accessibilityHidden(true)
                .padding(.bottom, 6)
                .diAppear()
            Text(verbatim: ShajraText.titleUrduLead)
                .font(DIFont.urduBody(scale: 1.7))
                .foregroundStyle(ShajraPalette.goldOnEmerald)
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .rightToLeft)
                .diGoldTextShimmer(highlight: Color(hex: 0xFFFBEA), delay: ShajraMotion.headerShimmerDelay)
                .diGoldGlow(radius: 12, opacity: 0.45)
                .diAppear(delay: 0.10)
            Text(verbatim: ShajraText.titleUrduSilsila)
                .font(DIFont.urduBody(scale: 0.95))
                .foregroundStyle(Color.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .rightToLeft)
                .diAppear(delay: 0.18)
            // Letter-spaced capitals: the title is always English.
            Text(verbatim: ShajraText.titleEnglish)
                .font(.caption.weight(.heavy))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel(Text(verbatim: ShajraText.titleEnglish))
                .diAppear(delay: 0.26)
        }
        .padding(.top, 22)
        .padding(.bottom, 24)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background {
            DIHeroBackground(cornerRadius: 30)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - The chain

/// The 13 links down the page, joined by the gold trunk on the leading side,
/// where the nodes sit: the right in Urdu.
private struct ShajraChain: View {
    /// The space the nodes are measured in.
    static let space = "shajra.chain"

    /// The centre of each node, down the chain, by its index.
    @State private var nodeCentres: [Int: CGFloat] = [:]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(ShajraText.entries) { entry in
                ShajraRow(entry: entry)
            }
        }
        .coordinateSpace(.named(Self.space))
        .background(alignment: .topLeading) {
            ShajraTrunk()
                .frame(width: ShajraRow.nodeSide, height: trunkLength)
                .padding(.top, trunkTop)
        }
        .onPreferenceChange(ShajraNodeKey.self) { centres in
            Task { @MainActor in
                nodeCentres = centres
            }
        }
    }

    private var firstIndex: Int { ShajraText.entries.first?.index ?? 0 }
    private var lastIndex: Int { ShajraText.entries.last?.index ?? 0 }

    /// The first node's centre.
    private var trunkTop: CGFloat {
        nodeCentres[firstIndex] ?? 0
    }

    /// From the first node's centre to the last's.
    private var trunkLength: CGFloat {
        guard let top = nodeCentres[firstIndex], let bottom = nodeCentres[lastIndex] else { return 0 }
        return max(bottom - top, 0)
    }
}

/// The centre of each node in the chain's space, by index.
private struct ShajraNodeKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// One link: its node on the trunk, and its card with the Urdu line over the
/// English one. VoiceOver reads it as one element, Urdu then English.
private struct ShajraRow: View {
    /// The node badge's side, and so the width of the trunk's column.
    static let nodeSide: CGFloat = 36

    let entry: ShajraEntry

    @State private var badgeIn = false
    @State private var flashOver = false
    @State private var cardIn = false
    @State private var urduIn = false
    @State private var englishIn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            node
                .padding(.top, 12)
            card
        }
        .accessibilityElement(children: .combine)
        .onAppear { arrive() }
    }

    // MARK: Node

    private var node: some View {
        ShajraNodeBadge(entry: entry)
            // A brief gold flash as it arrives: bright while it scales in,
            // settling as it lands.
            .shadow(
                color: DIColor.goldGlow.opacity(shows(flashOver) ? 0 : 0.95),
                radius: shows(flashOver) ? 2 : 14
            )
            .scaleEffect(shows(badgeIn) ? 1 : 0.6)
            .opacity(shows(badgeIn) ? 1 : 0)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ShajraNodeKey.self,
                        value: [entry.index: geo.frame(in: .named(ShajraChain.space)).midY]
                    )
                }
            )
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            urduLine
            Rectangle()
                .fill(hairline)
                .frame(height: 1)
                .opacity(shows(urduIn) ? 1 : 0)
                .accessibilityHidden(true)
            englishLine
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ShajraCardSurface(kind: entry.kind))
        .opacity(shows(cardIn) ? 1 : 0)
    }

    /// The supplication line in the Urdu face, right to left whatever the
    /// app's language, with a band of gold light passing over it.
    private var urduLine: some View {
        Text(verbatim: entry.urdu)
            .font(DIFont.urduBody())
            .foregroundStyle(urduInk)
            .lineSpacing(4)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .rightToLeft)
            .opacity(shows(urduIn) ? 1 : 0)
            .offset(y: shows(urduIn) ? 0 : 10)
            .diGoldTextShimmer(highlight: shimmerHighlight, delay: ShajraMotion.shimmerDelay(entry.index))
    }

    /// The website's English line, left to right whatever the app's language.
    private var englishLine: some View {
        Text(verbatim: entry.english)
            .font(.footnote.weight(.medium))
            .foregroundStyle(englishInk)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .leftToRight)
            .opacity(shows(englishIn) ? 1 : 0)
            .offset(y: shows(englishIn) ? 0 : 8)
    }

    private var urduInk: Color {
        switch entry.kind {
        case .prophet: return ShajraPalette.emeraldInk
        case .sheikh: return DIColor.textPrimary
        case .presentSheikh: return ShajraPalette.goldOnEmerald
        }
    }

    private var englishInk: Color {
        switch entry.kind {
        case .prophet: return ShajraPalette.emeraldInk.opacity(0.8)
        case .sheikh: return DIColor.textMuted
        case .presentSheikh: return Color.white.opacity(0.85)
        }
    }

    /// The thin gold hairline between the two lines.
    private var hairline: AnyShapeStyle {
        switch entry.kind {
        case .prophet:
            return AnyShapeStyle(Color(hex: 0xB48A2C).opacity(0.55))
        case .sheikh:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(hex: 0xE0B75F).opacity(0.15),
                        Color(hex: 0xE0B75F).opacity(0.8),
                        Color(hex: 0xE0B75F).opacity(0.15),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .presentSheikh:
            return AnyShapeStyle(Color(hex: 0xE0B75F).opacity(0.55))
        }
    }

    /// The light that passes over the Urdu: pale on the gold and emerald
    /// cards, deep gold on glass by day, pale at night.
    private var shimmerHighlight: Color {
        switch entry.kind {
        case .prophet, .presentSheikh:
            return Color(hex: 0xFFFBEA)
        case .sheikh:
            return colorScheme == .dark ? Color(hex: 0xFFF7DA) : Color(hex: 0xD9A93C)
        }
    }

    // MARK: Motion

    /// Whether a part shows: once it has arrived, and always under Reduce
    /// Motion.
    private func shows(_ arrived: Bool) -> Bool {
        arrived || reduceMotion
    }

    /// On first appearance, in turn down the chain: the badge scales in from
    /// 0.6 with a brief gold flash and the card fades in, the Urdu line
    /// rises in, and the English follows. Under Reduce Motion everything is
    /// simply there.
    private func arrive() {
        guard !badgeIn else { return }
        guard !reduceMotion else {
            badgeIn = true
            flashOver = true
            cardIn = true
            urduIn = true
            englishIn = true
            return
        }
        let start = ShajraMotion.rowDelay(entry.index)
        let urduStart = start + ShajraMotion.urduLag
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(start)) {
            badgeIn = true
        }
        withAnimation(.easeOut(duration: 0.9).delay(start)) {
            flashOver = true
        }
        withAnimation(.easeOut(duration: 0.35).delay(start)) {
            cardIn = true
        }
        withAnimation(.easeOut(duration: ShajraMotion.lineDuration).delay(urduStart)) {
            urduIn = true
        }
        withAnimation(.easeOut(duration: ShajraMotion.lineDuration).delay(urduStart + ShajraMotion.englishLag)) {
            englishIn = true
        }
    }
}

/// A link's card: gold for the Holy Prophet, the emerald hero for the
/// present Sheikh, glass for the Sheikhs between.
private struct ShajraCardSurface: ViewModifier {
    let kind: ShajraEntry.Kind

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        switch kind {
        case .prophet:
            content
                .background(shape.fill(ShajraPalette.prophetCard))
                .overlay(shape.stroke(Color.white.opacity(0.45), lineWidth: 1))
                .shadow(color: DIColor.goldGlow.opacity(0.35), radius: 14, y: 6)
        case .sheikh:
            content
                .diGlassPanel(cornerRadius: 20)
        case .presentSheikh:
            content
                .background {
                    DIHeroBackground(cornerRadius: 20)
                }
                .overlay(shape.stroke(Color(hex: 0xE0B75F).opacity(0.55), lineWidth: 1))
        }
    }
}

/// A node on the trunk: a 36 pt eight-pointed star, as Read's surah badges
/// are. Gold with the salutation for the Holy Prophet, emerald with its
/// number for each Sheikh, and gold-edged with a soft glow for the present
/// Sheikh.
private struct ShajraNodeBadge: View {
    let entry: ShajraEntry

    var body: some View {
        ZStack {
            DIOctagram(innerRatio: 0.76)
                .fill(badgeFill)
            if entry.kind == .presentSheikh {
                DIOctagram(innerRatio: 0.76)
                    .stroke(Color(hex: 0xE0B75F), lineWidth: 1.5)
            }
            mark
        }
        .frame(width: ShajraRow.nodeSide, height: ShajraRow.nodeSide)
        .shadow(color: glow, radius: entry.kind == .sheikh ? 3 : 8)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        if entry.kind == .prophet {
            // ﷺ
            Text(verbatim: "\u{FDFA}")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ShajraPalette.emeraldInk)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 4)
        } else {
            Text("\(entry.index)")
                .font(.system(size: 13, weight: .heavy).monospacedDigit())
                .foregroundStyle(entry.kind == .presentSheikh ? ShajraPalette.goldOnEmerald : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 5)
        }
    }

    private var badgeFill: AnyShapeStyle {
        switch entry.kind {
        case .prophet:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(hex: 0xFFE9A8), Color(hex: 0xE0B75F), Color(hex: 0xB48A2C)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .sheikh:
            return AnyShapeStyle(Color(hex: 0x0B7250))
        case .presentSheikh:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(hex: 0x0E8A60), Color(hex: 0x064B34)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var glow: Color {
        switch entry.kind {
        case .prophet: return DIColor.goldGlow.opacity(0.5)
        case .sheikh: return Color(hex: 0x064B34).opacity(0.25)
        case .presentSheikh: return DIColor.goldGlow.opacity(0.6)
        }
    }
}

// MARK: - Trunk

/// A vertical line down the middle of its frame.
private struct ShajraTrunkLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// The gold trunk joining the nodes, from the Holy Prophet's to the present
/// Sheikh's. It draws downward on first appearance; then a small gold light
/// travels down it every few seconds. Under Reduce Motion it is simply
/// there, without the light.
private struct ShajraTrunk: View {
    @State private var drawn = false
    /// When the page appeared: the light waits for the trunk to draw.
    @State private var appeared = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            ShajraTrunkLine()
                .trim(from: 0, to: (drawn || reduceMotion) ? 1 : 0)
                .stroke(ShajraPalette.trunk, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .shadow(color: DIColor.goldGlow.opacity(0.35), radius: 3)
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: scenePhase != .active)) { timeline in
                    light(at: timeline.date)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { draw() }
    }

    /// The small light, where it is on the trunk at `date`.
    private func light(at date: Date) -> some View {
        let pass = ShajraMotion.trunkLight(elapsed: date.timeIntervalSince(appeared))
        return GeometryReader { geo in
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [ShajraPalette.light.opacity(0), ShajraPalette.light.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: 26)
                    .offset(y: -13)
                Circle()
                    .fill(ShajraPalette.light)
                    .frame(width: 7, height: 7)
            }
            .shadow(color: DIColor.goldGlow.opacity(0.9), radius: 6)
            .opacity(pass.brightness)
            .position(x: geo.size.width / 2, y: geo.size.height * CGFloat(pass.position))
        }
    }

    private func draw() {
        guard !drawn else { return }
        guard !reduceMotion else {
            drawn = true
            return
        }
        withAnimation(.easeInOut(duration: ShajraMotion.trunkDuration).delay(ShajraMotion.trunkDelay)) {
            drawn = true
        }
    }
}

// MARK: - Closing dua

/// The Arabic dua that closes the Shajra: centred on glass, in the Qur'an
/// face and the Zikr ayah's ink, with a band of gold light passing over it.
private struct ShajraClosingDua: View {
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Text(verbatim: ShajraText.closingArabic)
            .font(DIFont.quranArabic(scale: 0.9))
            .foregroundStyle(ReadPalette.arabicInk)
            .multilineTextAlignment(.center)
            .lineSpacing(8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .environment(\.layoutDirection, .rightToLeft)
            .diGoldTextShimmer(
                highlight: isDark ? Color(hex: 0xFFF7DA) : Color(hex: 0xD9A93C),
                delay: ShajraMotion.closingShimmerDelay
            )
            .diGoldGlow(radius: isDark ? 12 : 8, opacity: isDark ? 0.5 : 0.3)
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
            .diGlassPanel(cornerRadius: 24)
            .diAppear(delay: ShajraMotion.closingDelay)
    }
}
