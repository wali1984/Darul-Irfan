import SwiftUI

// Shared UI vocabulary. Feature screens compose these instead of restyling
// their own cards/buttons, so the whole app reads as one calm system.

// MARK: - Card

/// Soft card surface used across all features.
struct DICard<Content: View>: View {
    var padding: CGFloat = DISpacing.md
    var background: Color = DIColor.surface
    var borderColor: Color = DIColor.border
    var borderWidth: CGFloat = 1
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            // Subtle depth so cards read as surfaces, not flat blocks — a warm
            // emerald-tinted shadow rather than flat black reads more premium.
            .shadow(color: DIColor.primaryDeep.opacity(0.10), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Section header

struct DISectionHeader: View {
    let titleKey: LocalizedStringKey
    var systemImage: String?

    var body: some View {
        HStack(spacing: DISpacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(DIColor.accent)
                    .accessibilityHidden(true)
            }
            Text(titleKey)
                .font(DIFont.subheading)
                .foregroundStyle(DIColor.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DISpacing.xs)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Buttons

private struct DIActionButtonSurface: ViewModifier {
    let primary: Bool
    let pressed: Bool
    var compact = false
    var destructive = false
    var minimumHeight: CGFloat? = nil
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
        content
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DISpacing.md)
            .padding(.vertical, DISpacing.sm)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: minimumHeight ?? (compact ? 44 : 50))
            .foregroundStyle(destructive ? DIColor.danger : (primary ? DIColor.onPrimary : DIColor.actionForeground))
            .background(LinearGradient(
                colors: primary ? [DIColor.primary, DIColor.primaryDeep] : [DIColor.surface, DIColor.sandstone],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .clipShape(shape)
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [DIColor.accent.opacity(0.65), DIColor.border.opacity(0.35)],
                               startPoint: .top, endPoint: .bottom), lineWidth: 1
            ).allowsHitTesting(false))
            .shadow(color: DIColor.primaryDeep.opacity(enabled && !pressed ? 0.18 : 0.06),
                    radius: pressed ? 2 : 6, x: 0, y: pressed ? 1 : 3)
            .opacity(enabled ? (pressed ? 0.9 : 1) : 0.48)
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: pressed)
    }
}

struct DIPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(DIActionButtonSurface(primary: true, pressed: configuration.isPressed))
    }
}

struct DISecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(DIActionButtonSurface(primary: false, pressed: configuration.isPressed))
    }
}

struct DICompactButtonStyle: ButtonStyle {
    var destructive = false
    var minimumHeight: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(DIActionButtonSurface(
            primary: false, pressed: configuration.isPressed, compact: true, destructive: destructive, minimumHeight: minimumHeight
        ))
    }
}

// MARK: - Empty & loading states

struct DIEmptyState: View {
    let systemImage: String
    let titleKey: LocalizedStringKey
    var messageKey: LocalizedStringKey?

    var body: some View {
        VStack(spacing: DISpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DIColor.textMuted)
                .accessibilityHidden(true)
            Text(titleKey)
                .font(DIFont.subheading)
                .foregroundStyle(DIColor.textPrimary)
                .multilineTextAlignment(.center)
            if let messageKey {
                Text(messageKey)
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DISpacing.xl)
    }
}

// MARK: - Badges

struct DIPillBadge: View {
    let text: String
    var color: Color = DIColor.primary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, DISpacing.sm)
            .padding(.vertical, DISpacing.xs)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Screen scaffold

/// Standard screen background + insets so tabs feel uniform. Layers a faint
/// Islamic geometric texture over the warm base so screens feel crafted, not
/// flat.
struct DIScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    DIColor.background
                    DIPatternTexture(tint: DIColor.accent, opacity: 0.04)
                }
                .ignoresSafeArea()
            )
    }
}

extension View {
    func diScreenBackground() -> some View {
        modifier(DIScreenBackground())
    }
}
