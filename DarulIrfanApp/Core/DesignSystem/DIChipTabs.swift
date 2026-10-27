import SwiftUI

/// A row of sections as chips, each as wide as its own name, scrolling
/// sideways when they do not all fit. Unlike `DISegmentedControl`, which
/// splits the width equally, no name is ever cut short - in Urdu, or at any
/// text size. The chosen chip scrolls into view.
struct DIChipTabs<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> LocalizedStringKey
    var icon: (Item) -> String? = { _ in nil }
    @Binding var selection: Item

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DISpacing.sm) {
                    ForEach(items, id: \.self) { item in
                        chip(item).id(item)
                    }
                }
                .padding(.horizontal, DISpacing.md)
                .padding(.vertical, 2)
            }
            .onChange(of: selection) { _, item in
                if reduceMotion {
                    proxy.scrollTo(item, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(item, anchor: .center) }
                }
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
    }

    private func chip(_ item: Item) -> some View {
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
                    Image(systemName: symbol).font(.subheadline.weight(.semibold))
                }
                Text(title(item))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize()
            }
            .foregroundStyle(selected ? DIColor.onPrimary : DIColor.textPrimary)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(DIColor.primary)
                        .matchedGeometryEffect(id: "di.chip.pill", in: namespace)
                        .shadow(color: DIColor.primaryDeep.opacity(0.3), radius: 5, y: 2)
                } else {
                    Capsule(style: .continuous)
                        .fill(DIColor.sandstone.opacity(0.55))
                        .overlay(Capsule(style: .continuous).stroke(DIColor.border, lineWidth: 1))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
