import SwiftUI
import UIKit

/// Interface lettering follows the selected language without changing scripture fonts.
private struct DIInterfaceTypography: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight?
    let design: Font.Design
    @Environment(\.locale) private var locale
    @AppStorage(AppFonts.nastaliqPreferenceKey) private var nastaliq = true

    private var font: Font {
        guard locale.language.languageCode?.identifier == "ur", nastaliq,
              let name = AppFonts.appleNastaliqName else {
            let base = Font.system(style, design: design)
            return weight.map { base.weight($0) } ?? base
        }
        let uiStyle: UIFont.TextStyle
        switch style {
        case .largeTitle: uiStyle = .largeTitle
        case .title: uiStyle = .title1
        case .title2: uiStyle = .title2
        case .title3: uiStyle = .title3
        case .headline: uiStyle = .headline
        case .subheadline: uiStyle = .subheadline
        case .callout: uiStyle = .callout
        case .footnote: uiStyle = .footnote
        case .caption: uiStyle = .caption1
        case .caption2: uiStyle = .caption2
        default: uiStyle = .body
        }
        // Use the standard point size here; Font.custom applies Dynamic Type once.
        let size = UIFont.preferredFont(forTextStyle: uiStyle,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
        let result = Font.custom(name, size: size, relativeTo: style)
        if let weight { return result.weight(weight) }
        return style == .headline ? result.weight(.semibold) : result
    }

    func body(content: Content) -> some View { content.font(font) }
}

extension View {
    func diInterfaceFont(_ style: Font.TextStyle, weight: Font.Weight? = nil,
                         design: Font.Design = .default) -> some View {
        modifier(DIInterfaceTypography(style: style, weight: weight, design: design))
    }
}
