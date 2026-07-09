import SwiftUI

// Shared UI vocabulary. Feature screens compose these instead of restyling
// their own cards/buttons, so the whole app reads as one calm system.

// MARK: - Card

/// Soft card surface used across all features.
struct DICard<Content: View>: View {
    var padding: CGFloat = DISpacing.md
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DIColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DIRadius.lg, style: .continuous)
                    .stroke(DIColor.border, lineWidth: 1)
            )
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

struct DIPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(DIColor.onPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(DIColor.primary.opacity(configuration.isPressed ? 0.85 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
    }
}

struct DISecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(DIColor.primary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(DIColor.surface.opacity(configuration.isPressed ? 0.7 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous)
                    .stroke(DIColor.primary, lineWidth: 1)
            )
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

/// Standard screen background + insets so tabs feel uniform.
struct DIScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DIColor.background.ignoresSafeArea())
    }
}

extension View {
    func diScreenBackground() -> some View {
        modifier(DIScreenBackground())
    }
}
