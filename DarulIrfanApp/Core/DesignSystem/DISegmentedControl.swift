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

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                segment(item)
            }
        }
        .padding(4)
        .background(Capsule(style: .continuous).fill(DIColor.sandstone.opacity(0.55)))
        .overlay(Capsule(style: .continuous).stroke(DIColor.border, lineWidth: 1))
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
            .foregroundStyle(selected ? DIColor.onPrimary : DIColor.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(DIColor.primary)
                        .matchedGeometryEffect(id: "di.segment.pill", in: namespace)
                        .shadow(color: DIColor.primaryDeep.opacity(0.3), radius: 5, y: 2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
