import SwiftUI

/// An animated pill segmented control: the selected pill slides between
/// segments (`matchedGeometryEffect`), with optional icons, haptics, and a
/// spring. A modern, app-native replacement for `.pickerStyle(.segmented)`
/// (which reads like a web menu). Reduce-Motion falls back to an instant swap.
struct DISegmentedControl<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> LocalizedStringKey
    var icon: (Item) -> String? = { _ in nil }
    @Binding var selection: Item
    /// On a dark (emerald) surface the track and labels turn light and the
    /// chosen pill gold, so the control reads against it.
    var onDark = false

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                segment(item)
            }
        }
        .padding(4)
        .background(Capsule(style: .continuous).fill(onDark ? Color.white.opacity(0.10) : DIColor.sandstone.opacity(0.55)))
        .overlay(Capsule(style: .continuous).stroke(onDark ? Color.white.opacity(0.18) : DIColor.border, lineWidth: 1))
    }

    private func labelColor(selected: Bool) -> Color {
        if onDark { return selected ? DIColor.primaryDeep : DIColor.onPrimary.opacity(0.8) }
        return selected ? DIColor.onPrimary : DIColor.textMuted
    }

    private func segment(_ item: Item) -> some View {
        let selected = item == selection
        return Button {
            DIHaptics.soft()
            if reduceMotion {
                selection = item
            } else {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { selection = item }
            }
        } label: {
            HStack(spacing: 6) {
                if let symbol = icon(item) {
                    Image(systemName: symbol).font(.caption2.weight(.semibold))
                }
                Text(title(item))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(labelColor(selected: selected))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(onDark ? AnyShapeStyle(DIGradient.goldSheen) : AnyShapeStyle(DIColor.primary))
                        .matchedGeometryEffect(id: "di.segment.pill", in: namespace)
                        .shadow(color: onDark ? DIColor.goldGlow.opacity(0.45) : DIColor.primaryDeep.opacity(0.3),
                                radius: onDark ? 7 : 5, y: 2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // VoiceOver announces which segment is chosen, as for a system picker.
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
