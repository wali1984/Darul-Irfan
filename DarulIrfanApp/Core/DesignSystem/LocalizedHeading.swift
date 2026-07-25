import SwiftUI

extension View {
    /// The large page title at the top of a screen. Per product choice the
    /// large title is hidden for Urdu (Urdu screens start title-less), while
    /// English/System keep the normal large navigation title. Section headings
    /// inside the page are unaffected.
    @ViewBuilder
    func diPageHeading(_ title: LocalizedStringKey, language: AppLanguage) -> some View {
        if language == .urdu {
            self.navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
        } else {
            self.navigationTitle(title)
        }
    }
}
