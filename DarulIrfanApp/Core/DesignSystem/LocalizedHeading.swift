import SwiftUI

/// The large page title at the top of a screen. Per product choice the large
/// title is hidden when the UI is Urdu (Urdu screens start title-less), while
/// English/System keep the normal large navigation title. Section headings
/// inside the page are unaffected.
///
/// It reads the active UI locale from the environment (set by the app root),
/// so screens don't need to thread the language setting through themselves.
private struct DIPageHeading: ViewModifier {
    let title: LocalizedStringKey
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        if locale.language.languageCode?.identifier == "ur" {
            content
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content.navigationTitle(title)
        }
    }
}

extension View {
    func diPageHeading(_ title: LocalizedStringKey) -> some View {
        modifier(DIPageHeading(title: title))
    }
}
