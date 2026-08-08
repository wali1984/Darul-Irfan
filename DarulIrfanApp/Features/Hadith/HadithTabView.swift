import SwiftUI

// MARK: - Navigation

/// Destinations reachable inside the Hadith reader's navigation stack.
///
/// Value-based routing (rather than a `NavigationLink` that builds its own
/// destination) is what lets the Read tab hold this reader's history outside
/// the view, so switching to the Quran and back returns to the same place.
enum HadithRoute: Hashable {
    case collection(HadithBook)
    /// Open a collection scrolled to a specific narration — e.g. a tapped
    /// search result. Carries the printed number so the reader can jump to it.
    case hadith(HadithBook, String)
}

// MARK: - Reader entry point

/// Hadith reader root: the bundled collections, opening into a paged reader.
///
/// A peer of `QuranTabView`, never nested inside it. Both are presented by
/// `ReadTabView` as equals.
struct HadithTabView: View {
    let dependencies: AppDependencies
    let appState: AppState
    @Binding var navigationPath: [HadithRoute]
    var readerSelection: Binding<ReadSection>?
    var onShowAllReaders: (() -> Void)?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            HadithHomeView(dependencies: dependencies, appState: appState)
                .navigationDestination(for: HadithRoute.self) { route in
                    switch route {
                    case .collection(let book):
                        HadithBookView(
                            book: book,
                            repository: dependencies.hadithRepository,
                            appState: appState
                        )
                    case .hadith(let book, let displayNumber):
                        HadithBookView(
                            book: book,
                            repository: dependencies.hadithRepository,
                            appState: appState,
                            initialHadith: displayNumber
                        )
                    }
                }
                // Applied inside the stack so it lands in this reader's own
                // navigation bar.
                .modifier(OptionalReaderSwitch(
                    selection: readerSelection,
                    onShowAll: onShowAllReaders
                ))
        }
    }
}

/// Adds the reader switch only when the host provides one, so the reader still
/// works standalone (previews, tests, a future deep-linked presentation).
struct OptionalReaderSwitch: ViewModifier {
    let selection: Binding<ReadSection>?
    let onShowAll: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let selection, let onShowAll {
            content.readerSwitch(selection: selection, onShowAll: onShowAll)
        } else {
            content
        }
    }
}
