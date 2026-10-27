import SwiftUI

/// A search hit that opens what it names: an ayah in the Quran reader, a
/// library work in its reader, a bayan in the player, an event's details.
/// Search results used to be rows with nothing behind them.
@MainActor
struct SearchResultLink<RowContent: View>: View {
    let result: SearchResult
    let dependencies: AppDependencies
    let appState: AppState
    /// Closes the search sheet before the Quran tab takes over.
    let close: () -> Void
    @ViewBuilder let label: () -> RowContent

    @State private var video: SearchVideo?

    var body: some View {
        Group {
            switch result.domain {
            case .library:
                NavigationLink {
                    ContentItemDetailView(
                        itemID: result.itemID,
                        dependencies: dependencies,
                        appState: appState,
                        libraryViewModel: LibraryViewModel(contentRepository: dependencies.contentRepository)
                    )
                } label: { label() }
            case .events:
                NavigationLink {
                    SearchEventDestination(eventID: result.itemID, dependencies: dependencies)
                } label: { label() }
            case .quran:
                Button { openAyah() } label: { label() }
            case .media:
                Button { Task { await play() } } label: { label() }
            }
        }
        .buttonStyle(.plain)
        .sheet(item: $video) { video in YouTubePlayerSheet(videoID: video.id, title: video.title) }
    }

    /// "2:255" opens the reader at that ayah, on the Quran tab.
    private func openAyah() {
        let parts = result.itemID.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        DIHaptics.soft()
        close()
        // After the sheet has gone, so the tab switch is not hidden behind it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(name: .didReceiveAppDeepLink, object: "quran")
            NotificationCenter.default.post(name: .openQuranAyah, object: QuranAyahLink(surah: parts[0], ayah: parts[1]))
        }
    }

    /// Audio plays in the app's own player; a video-only bayan opens its player.
    private func play() async {
        guard let media = try? await dependencies.mediaRepository.item(id: result.itemID) else { return }
        if let url = media.streamUrl.flatMap({ URL(string: $0) }) {
            DIHaptics.soft()
            dependencies.audioPlayer.play(
                AudioPlayableItem(id: media.id, title: media.title, subtitle: media.speaker, url: url, mediaItemID: media.id),
                queue: []
            )
        } else if let videoID = media.youtubeId, !videoID.isEmpty {
            video = SearchVideo(id: videoID, title: media.title)
        }
    }
}

private struct SearchVideo: Identifiable {
    let id: String
    let title: String
}

/// Loads an event by id, then shows its details.
private struct SearchEventDestination: View {
    let eventID: String
    let dependencies: AppDependencies
    @State private var event: CommunityEvent?
    @State private var loaded = false

    var body: some View {
        Group {
            if let event {
                EventDetailView(event: event, notifications: dependencies.notifications)
            } else if loaded {
                DIEmptyState(systemImage: "calendar", titleKey: "Event not found",
                             messageKey: "It may have ended or been removed.")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            event = (try? await dependencies.eventsRepository.events())?.first { $0.id == eventID }
            loaded = true
        }
    }
}
