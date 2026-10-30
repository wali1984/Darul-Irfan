import SwiftUI

// The Halqah pages' own building blocks, made from the design system's
// tokens: the frosted header over the living emerald gradient, the bento
// tiles a Halqah is run from, the role badge, the ring that counts down to
// the next zikr, and the light that marks what is live. Nothing here talks
// to the server: every tile runs the action its page hands it.
//
// Motion is quiet and means something. A tile springs and taps when it is
// pressed, its symbol bounces when let go and pulses while something new
// waits in it, and only what is live breathes. Under Reduce Motion nothing
// loops.

// MARK: - Roles

extension GroupRole {
    /// A crown for the Super admin, a shield for an Administrator, a key for
    /// an Admin.
    var badgeSymbol: String {
        switch self {
        case .superadmin: "crown.fill"
        case .administrator: "shield.lefthalf.filled"
        case .admin: "key.fill"
        case .member: "person.fill"
        }
    }

    /// The role's name in the app's language, for what VoiceOver says.
    var spokenTitle: String {
        switch self {
        case .superadmin: String(localized: "Super admin")
        case .administrator: String(localized: "Administrator")
        case .admin: String(localized: "Admin")
        case .member: String(localized: "Member")
        }
    }
}

/// A role as a small capsule: its symbol and its name.
struct HalqahRoleBadge: View {
    let role: GroupRole
    /// Gold on the dark glass header; emerald on a page's paper.
    var onGlass = false
    /// What VoiceOver says in place of "Your role: ...".
    var accessibilityKey: LocalizedStringKey? = nil

    var body: some View {
        Label {
            Text(role.title)
        } icon: {
            Image(systemName: role.badgeSymbol)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, DISpacing.sm)
        .padding(.vertical, DISpacing.xs)
        .background(Capsule().fill(tint.opacity(onGlass ? 0.16 : 0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityKey.map { Text($0) } ?? Text("Your role: \(role.spokenTitle)"))
    }

    private var tint: Color {
        if onGlass { return DIColor.goldGlow }
        return role == .member ? DIColor.textMuted : DIColor.primary
    }
}

/// Whether a Halqah is live: a pulsing light and what is live, or a quiet
/// "no session now".
struct HalqahLiveChip: View {
    /// A meeting (true) or a zikr (false) is live; nil when nothing is.
    let liveIsMeeting: Bool?
    var onGlass = false

    var body: some View {
        HStack(spacing: DISpacing.xs + 2) {
            if let liveIsMeeting {
                DILivePulse(color: onGlass ? DIColor.goldGlow : DIColor.primary, size: 7)
                Text(liveIsMeeting ? "Meeting live" : "Zikr live")
                    .font(.caption.weight(.bold))
            } else {
                Image(systemName: "moon.stars")
                    .font(.caption)
                    .accessibilityHidden(true)
                Text("No session now")
                    .font(.caption.weight(.medium))
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, DISpacing.sm)
        .padding(.vertical, DISpacing.xs)
        .background(Capsule().fill(fill))
        .accessibilityElement(children: .combine)
    }

    private var foreground: Color {
        if onGlass { return liveIsMeeting == nil ? Color.white.opacity(0.75) : DIColor.goldGlow }
        return liveIsMeeting == nil ? DIColor.textMuted : DIColor.primary
    }

    private var fill: Color {
        if onGlass { return Color.white.opacity(liveIsMeeting == nil ? 0.08 : 0.16) }
        return (liveIsMeeting == nil ? DIColor.textMuted : DIColor.primary).opacity(0.12)
    }
}

// MARK: - Glass header

/// A fact the page already holds, shown as a chip under the header's title.
struct HalqahFact: Identifiable {
    let id: String
    let systemImage: String
    let text: Text
}

/// The living emerald gradient behind the glass, with two soft lights for
/// the frost to catch and the Silsila's pattern faintly over it.
private struct HalqahGradientBackdrop: View {
    var isLive: Bool

    var body: some View {
        ZStack {
            DIGradient.hero()
            Circle()
                .fill(DIColor.goldGlow.opacity(isLive ? 0.42 : 0.26))
                .frame(width: 190, height: 190)
                .blur(radius: 50)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(y: -50)
            Circle()
                .fill(DIColor.primary.opacity(0.55))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .offset(y: 70)
        }
        .diPatternOverlay(tint: .white, opacity: 0.06)
        .accessibilityHidden(true)
    }
}

/// Frosted glass over the living gradient: the header of each Halqah page.
/// Always drawn dark, so its white type reads the same in light and dark
/// mode; and the page's only blur, however long the page grows.
struct HalqahGlassHeader<Content: View>: View {
    var isLive = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        let outer = RoundedRectangle(cornerRadius: DIRadius.lg + 6, style: .continuous)
        let inner = RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
        content()
            .padding(DISpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: inner)
            .overlay(inner.strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .padding(DISpacing.sm)
            .background { HalqahGradientBackdrop(isLive: isLive) }
            .clipShape(outer)
            .overlay {
                if isLive {
                    outer.strokeBorder(DIColor.goldGlow.opacity(0.55), lineWidth: 1)
                }
            }
            // The shadow hangs from a plain shape of its own, so the live
            // light moving inside never has it drawn again.
            .background {
                outer.fill(DIColor.primaryDeep)
                    .shadow(color: DIColor.primaryDeep.opacity(0.30), radius: 16, x: 0, y: 8)
            }
            .environment(\.colorScheme, .dark)
    }
}

/// The top of a Halqah's page: its name and description, the viewer's role,
/// whether it is live, and facts the page already holds - so a Super admin,
/// an Administrator, an Admin and a member each see at once where they stand.
struct HalqahCommandHeader: View {
    let name: String
    let description: String?
    let role: GroupRole
    /// A meeting (true) or a zikr (false) is live; nil when nothing is.
    let liveIsMeeting: Bool?
    var facts: [HalqahFact] = []

    var body: some View {
        HalqahGlassHeader(isLive: liveIsMeeting != nil) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DISpacing.sm) {
                        HalqahRoleBadge(role: role, onGlass: true)
                        Spacer(minLength: DISpacing.sm)
                        HalqahLiveChip(liveIsMeeting: liveIsMeeting, onGlass: true)
                    }
                    VStack(alignment: .leading, spacing: DISpacing.xs) {
                        HalqahRoleBadge(role: role, onGlass: true)
                        HalqahLiveChip(liveIsMeeting: liveIsMeeting, onGlass: true)
                    }
                }
                Text(LocalizedStringKey(name))
                    .font(DIFont.heading)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let description, !description.isEmpty {
                    Text(verbatim: description)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !facts.isEmpty {
                    HalqahFactRow(facts: facts)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct HalqahFactRow: View {
    let facts: [HalqahFact]

    var body: some View {
        // In a row while they fit; one under another at large text sizes.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DISpacing.xs) {
                ForEach(facts) { chip($0) }
            }
            VStack(alignment: .leading, spacing: DISpacing.xs) {
                ForEach(facts) { chip($0) }
            }
        }
    }

    private func chip(_ fact: HalqahFact) -> some View {
        Label {
            fact.text
        } icon: {
            Image(systemName: fact.systemImage)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.white.opacity(0.9))
        .padding(.horizontal, DISpacing.sm)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.12)))
    }
}

// MARK: - Surfaces

/// A tile's surface: paper, a little translucent over the page's pattern,
/// lit along its top edge, with a hairline in the tile's colour. No blur, so
/// a page of tiles stays light to draw.
struct HalqahGlassSurface: View {
    var tint: Color = DIColor.primary
    var cornerRadius: CGFloat = DIRadius.lg

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(DIColor.surface.opacity(0.88))
            .overlay {
                shape.fill(LinearGradient(colors: [tint.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), tint.opacity(0.25), DIColor.border.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: DIColor.primaryDeep.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

extension View {
    /// Lays the view on a Halqah glass card, padded as a `DICard` is.
    func halqahCard(tint: Color = DIColor.primary) -> some View {
        self
            .padding(DISpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HalqahGlassSurface(tint: tint))
    }

    /// One VoiceOver element for a tile: its name, its live line as the
    /// value, and what it does as the hint.
    func halqahTileAccessibility(titleKey: LocalizedStringKey, value: Text?, hintKey: LocalizedStringKey?) -> some View {
        self
            .accessibilityLabel(Text(titleKey))
            .accessibilityValue(value ?? Text(verbatim: ""))
            .accessibilityHint(hintKey.map { Text($0) } ?? Text(verbatim: ""))
    }
}

extension DynamicTypeSize {
    /// Side by side as usual; one above the other at the largest text sizes,
    /// so no text is squeezed into a sliver beside a large symbol.
    func halqahRowLayout(alignment: VerticalAlignment = .center, spacing: CGFloat = DISpacing.md) -> AnyLayout {
        isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
    }
}

// MARK: - Tiles

private struct HalqahTilePressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// A tile is held down; its symbol bounces when it is let go.
    var halqahTilePressed: Bool {
        get { self[HalqahTilePressedKey.self] }
        set { self[HalqahTilePressedKey.self] = newValue }
    }
}

/// Presses like a physical tile: a small spring, and a light tap when let go.
struct HalqahTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.halqahTilePressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { wasPressed, isPressed in
                wasPressed && !isPressed
            }
    }
}

/// What a tile shows: its symbol, its name, and a live line beneath from
/// what the page already holds.
struct HalqahTileLabel: View {
    let titleKey: LocalizedStringKey
    var subtitle: Text? = nil
    let systemImage: String
    var tint: Color = DIColor.primary
    /// A count at the tile's corner, such as new dua requests.
    var badge: Int? = nil
    /// Something new waits here, or is live: the symbol pulses.
    var isAlive = false
    var showsChevron = false
    /// Across a row rather than stacked, for a tile the width of the page.
    var axis: Axis = .vertical

    @Environment(\.halqahTilePressed) private var pressed
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title3) private var iconBox: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var stackedMinHeight: CGFloat = 112
    @ScaledMetric(relativeTo: .body) private var rowMinHeight: CGFloat = 56
    @State private var bounces = 0

    var body: some View {
        Group {
            if axis == .horizontal {
                HStack(alignment: .center, spacing: DISpacing.md) {
                    symbol
                    texts
                    Spacer(minLength: 0)
                    accessories
                }
                .frame(maxWidth: .infinity, minHeight: rowMinHeight, maxHeight: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: DISpacing.sm) {
                    HStack(alignment: .top, spacing: DISpacing.sm) {
                        symbol
                        Spacer(minLength: 0)
                        accessories
                    }
                    Spacer(minLength: 0)
                    texts
                }
                // Tiles in a row share one height; at the largest text sizes
                // they stand one to a row and need no minimum.
                .frame(
                    maxWidth: .infinity,
                    minHeight: typeSize.isAccessibilitySize ? nil : stackedMinHeight,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
            }
        }
        .padding(DISpacing.md)
        .background(HalqahGlassSurface(tint: tint))
        .contentShape(RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))
        .opacity(isEnabled ? 1 : 0.55)
        .onChange(of: pressed) { _, isPressed in
            if !isPressed { bounces += 1 }
        }
    }

    private var symbol: some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(tint)
            .symbolEffect(.bounce, value: reduceMotion ? 0 : bounces)
            .symbolEffect(.pulse, isActive: isAlive && !reduceMotion)
            .frame(width: iconBox, height: iconBox)
            .background(Circle().fill(tint.opacity(0.14)))
            .accessibilityHidden(true)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titleKey)
                .font(.headline)
                .foregroundStyle(DIColor.textPrimary)
            if let subtitle {
                subtitle
                    .font(.footnote)
                    .foregroundStyle(isAlive ? tint : DIColor.textMuted)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var accessories: some View {
        if let badge, badge > 0 {
            Text(verbatim: badge > 99 ? "99+" : "\(badge)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(Capsule().fill(DIColor.danger))
                .accessibilityHidden(true)
        }
        if showsChevron {
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DIColor.textMuted)
                .accessibilityHidden(true)
        }
    }
}

/// One action in a tile grid.
struct HalqahTileItem: Identifiable {
    let id: String
    let titleKey: LocalizedStringKey
    var subtitle: Text? = nil
    let systemImage: String
    var tint: Color = DIColor.primary
    var badge: Int? = nil
    var isAlive = false
    var hintKey: LocalizedStringKey? = nil
    let action: () -> Void
}

/// A tile that acts. To VoiceOver it is one element: the tile's name, its
/// live line as the value, and what it does as the hint.
struct HalqahTile: View {
    let item: HalqahTileItem
    var axis: Axis = .vertical

    var body: some View {
        Button(action: item.action) {
            HalqahTileLabel(
                titleKey: item.titleKey,
                subtitle: item.subtitle,
                systemImage: item.systemImage,
                tint: item.tint,
                badge: item.badge,
                isAlive: item.isAlive,
                axis: axis
            )
        }
        .buttonStyle(HalqahTileButtonStyle())
        .halqahTileAccessibility(titleKey: item.titleKey, value: item.subtitle, hintKey: item.hintKey)
    }
}

/// Tiles two to a row, each row one height, a lone last tile across the
/// width. At the largest text sizes, one to a row so no title is cut short.
struct HalqahTileGrid: View {
    let items: [HalqahTileItem]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: DISpacing.sm) {
            if typeSize.isAccessibilitySize {
                ForEach(items) { item in
                    HalqahTile(item: item)
                        .diScrollReveal()
                }
            } else {
                ForEach(rows) { row in
                    HStack(spacing: DISpacing.sm) {
                        ForEach(row.items) { item in
                            HalqahTile(item: item, axis: row.items.count == 1 ? .horizontal : .vertical)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .diScrollReveal()
                }
            }
        }
    }

    private struct Row: Identifiable {
        let items: [HalqahTileItem]
        var id: String { items.map(\.id).joined(separator: "+") }
    }

    private var rows: [Row] {
        stride(from: 0, to: items.count, by: 2).map { start in
            Row(items: Array(items[start..<min(start + 2, items.count)]))
        }
    }
}

/// Two tiles side by side, one height; one above the other at the largest
/// text sizes. For tiles that are links rather than buttons.
struct HalqahTilePair<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: DISpacing.sm) {
                leading()
                trailing()
            }
        } else {
            HStack(spacing: DISpacing.sm) {
                leading()
                trailing()
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The large tile that starts a session: emerald, with a ring of light
/// travelling its edge and, while the Halqah is live, a breathing halo.
struct HalqahHeroTileLabel: View {
    let titleKey: LocalizedStringKey
    let subtitle: Text
    let systemImage: String
    var isLive = false

    @Environment(\.halqahTilePressed) private var pressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var iconBox: CGFloat = 56
    @State private var bounces = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
        let layout = typeSize.halqahRowLayout()
        layout {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(DIColor.goldGlow)
                .symbolEffect(.variableColor.iterative, isActive: isLive && !reduceMotion)
                .symbolEffect(.bounce, value: reduceMotion ? 0 : bounces)
                .frame(width: iconBox, height: iconBox)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .overlay(Circle().strokeBorder(DIColor.goldGlow.opacity(0.4), lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DISpacing.xs) {
                Text(titleKey)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !typeSize.isAccessibilitySize {
                Image(systemName: "chevron.forward")
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .accessibilityHidden(true)
            }
        }
        .padding(DISpacing.md + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(DIGradient.emerald)
                .overlay { shape.fill(DIGradient.auraGold).opacity(0.6) }
                .diPatternOverlay(tint: .white, opacity: 0.06)
                .clipShape(shape)
                .shadow(color: DIColor.primaryDeep.opacity(0.25), radius: 12, x: 0, y: 6)
        }
        .modifier(HalqahLightBorder(cornerRadius: DIRadius.lg))
        .modifier(HalqahLiveHalo(color: DIColor.goldGlow, cornerRadius: DIRadius.lg, isActive: isLive))
        .contentShape(shape)
        .onChange(of: pressed) { _, isPressed in
            if !isPressed { bounces += 1 }
        }
    }
}

// MARK: - Live light

/// A thin ring of light that travels slowly round the edge of what to press
/// now. It stands still under Reduce Motion and while the app is not in
/// front.
struct HalqahLightBorder: ViewModifier {
    var cornerRadius: CGFloat
    var lineWidth: CGFloat = 1.5
    var isActive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        if isActive {
            content.overlay {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion || scenePhase != .active)) { timeline in
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            AngularGradient(
                                colors: [
                                    DIColor.goldGlow, Color.white.opacity(0.3), DIColor.accent.opacity(0.15),
                                    Color.white.opacity(0.3), DIColor.goldGlow
                                ],
                                center: .center,
                                angle: .degrees(reduceMotion ? 0 : Self.turn(at: timeline.date) * 360)
                            ),
                            lineWidth: lineWidth
                        )
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        } else {
            content
        }
    }

    /// One slow turn every eight seconds.
    static func turn(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8
    }
}

/// A soft halo that breathes behind what is live; it stays still under
/// Reduce Motion. Only its opacity moves, so it costs little to draw.
struct HalqahLiveHalo: ViewModifier {
    var color: Color = DIColor.primary
    var cornerRadius: CGFloat = DIRadius.md
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.background {
            if isActive {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                if reduceMotion {
                    shape.fill(color).blur(radius: 10).opacity(0.35)
                } else {
                    PhaseAnimator([0.2, 0.6]) { level in
                        shape.fill(color).blur(radius: 12).opacity(level)
                    } animation: { _ in
                        .easeInOut(duration: 1.8)
                    }
                }
            }
        }
    }
}

/// The button that joins what is live. Emerald when it can be pressed and,
/// while the session or room is live, ringed with travelling light and a
/// breathing halo; sandstone and quiet while it cannot be pressed yet.
struct HalqahLiveButtonStyle: ButtonStyle {
    var isLive: Bool

    func makeBody(configuration: Configuration) -> some View {
        HalqahLiveButtonBody(configuration: configuration, isLive: isLive)
    }
}

private struct HalqahLiveButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isLive: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
        let lit = isLive && isEnabled
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? DIColor.onPrimary : DIColor.textMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DISpacing.md)
            .padding(.vertical, DISpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if isEnabled {
                    shape.fill(DIGradient.emerald)
                } else {
                    shape.fill(DIColor.sandstone)
                }
            }
            .overlay {
                if !isEnabled {
                    shape.strokeBorder(DIColor.border, lineWidth: 1)
                }
            }
            .modifier(HalqahLightBorder(cornerRadius: DIRadius.md, isActive: lit))
            .modifier(HalqahLiveHalo(color: DIColor.primary, cornerRadius: DIRadius.md, isActive: lit))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .medium), trigger: configuration.isPressed) { wasPressed, isPressed in
                wasPressed && !isPressed
            }
    }
}

// MARK: - Countdown ring

/// A ring that fills as the next zikr comes near: empty just after the one
/// before, full when it begins. Inside, the time left while it is less than
/// a day away, otherwise its day and time. It fills clockwise in both
/// reading directions, as a clock's hand turns.
struct HalqahCountdownRing: View {
    let start: Date
    /// The occurrence before, where the ring starts to fill; a day before
    /// `start` when not known.
    var since: Date?
    let now: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var diameter: CGFloat = 92

    var body: some View {
        let progress = Self.progress(at: now, start: start, since: since)
        ZStack {
            Circle()
                .stroke(DIColor.primary.opacity(0.14), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [DIColor.primary, DIColor.accent, DIColor.goldGlow, DIColor.primary],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .environment(\.layoutDirection, .leftToRight)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: progress)
            centre
                .padding(14)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Time until the next zikr"))
        .accessibilityValue(start <= now ? Text("The zikr time has begun") : Text(start, style: .relative))
    }

    @ViewBuilder
    private var centre: some View {
        if start <= now {
            VStack(spacing: 2) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                // The ring's own word ("ابھی" in Urdu), not the app-wide
                // "Now" that other screens use.
                Text("Right now")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(DIColor.primary)
        } else if start.timeIntervalSince(now) < 86_400 {
            Text(start, style: .timer)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(DIColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        } else {
            VStack(spacing: 0) {
                Text(start, format: .dateTime.weekday(.abbreviated))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DIColor.primary)
                Text(start, format: .dateTime.hour().minute())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(DIColor.textMuted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }

    /// How far the ring has filled at `now`, from 0 to 1.
    static func progress(at now: Date, start: Date, since: Date?) -> Double {
        let from = since ?? start.addingTimeInterval(-86_400)
        let span = start.timeIntervalSince(from)
        guard span > 0 else { return 1 }
        return min(max(now.timeIntervalSince(from) / span, 0), 1)
    }
}

// MARK: - Small marks

/// A meeting's day as a small emerald calendar leaf, in the phone's own time.
struct HalqahDateTile: View {
    let date: Date
    @ScaledMetric(relativeTo: .title2) private var side: CGFloat = 54

    var body: some View {
        VStack(spacing: 0) {
            Text(date, format: .dateTime.weekday(.abbreviated))
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
            Text(date, format: .dateTime.day())
                .font(.title2.weight(.bold).monospacedDigit())
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(DIColor.onPrimary)
        .frame(width: side, height: side)
        .background(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous).fill(DIGradient.emerald))
        .accessibilityHidden(true)
    }
}

/// A Halqah's emblem: the first letter of its name in the app's language,
/// on the Silsila's eight-point star.
struct HalqahMonogram: View {
    let name: String
    var isLive = false
    @ScaledMetric(relativeTo: .title2) private var side: CGFloat = 46

    var body: some View {
        Text(verbatim: initial)
            .font(.system(.title3, design: .serif).weight(.bold))
            .foregroundStyle(DIColor.onPrimary)
            .frame(width: side, height: side)
            .background(DIOctagram(innerRatio: 0.72).fill(DIGradient.emerald))
            .overlay(DIOctagram(innerRatio: 0.72).stroke(DIColor.accent.opacity(isLive ? 0.95 : 0.55), lineWidth: isLive ? 1.5 : 1))
            .accessibilityHidden(true)
    }

    /// The name as the page shows it: a Halqah named in the catalogue reads
    /// in Urdu when the app does.
    private var initial: String {
        let shown = NSLocalizedString(name, comment: "")
        return shown.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? ""
    }
}

/// One figure on the Super admin's dashboard: a count, what it counts, and a
/// pulse while something it counts is live.
struct HalqahStat: View {
    let value: Int
    let labelKey: LocalizedStringKey
    let systemImage: String
    var isLive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DISpacing.xs + 2) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DIColor.goldGlow)
                if isLive {
                    DILivePulse(color: DIColor.goldGlow, size: 6)
                }
            }
            Text(value, format: .number)
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(labelKey)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DISpacing.sm)
        .background(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous).fill(Color.white.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Next zikr

enum HalqahSchedule {
    /// A Halqah's zikr time at its next occurrence, for the countdown.
    struct Upcoming: Equatable {
        /// The zikr time as the Halqah's admins set it: its title and days.
        let session: ZikrSession
        /// This occurrence's start: under way now, or next.
        let start: Date
        /// The occurrence before it, from which the countdown ring fills.
        let since: Date?
    }

    /// The zikr time that is under way or comes next. A time set against a
    /// prayer at Dar-ul-Irfan is resolved for today first, as its row does.
    static func nextZikr(in sessions: [ZikrSession], at now: Date, calculator: (any PrayerCalculationServicing)?) -> Upcoming? {
        var best: (session: ZikrSession, resolved: ZikrSession, start: Date)?
        for session in sessions {
            let resolved: ZikrSession
            if let calculator {
                resolved = ZikrAnchorResolver.resolved(session, at: now, calculator: calculator)
            } else {
                resolved = session
            }
            guard let start = ZikrScheduleMath.currentOrNextOccurrence(of: resolved, at: now) else { continue }
            if let current = best, current.start <= start { continue }
            best = (session, resolved, start)
        }
        guard let best else { return nil }
        // The occurrence before, at the same resolved time: a day earlier for
        // a daily zikr, a week for a weekly one.
        let since = ZikrOccurrences.starts(
            of: best.resolved,
            after: best.start.addingTimeInterval(-8 * 86_400),
            count: 9,
            calculator: nil
        )
        .last { $0 < best.start }
        return Upcoming(session: best.session, start: best.start, since: since)
    }
}
