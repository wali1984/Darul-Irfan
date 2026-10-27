import SwiftUI

/// One private group: its meeting link, and what administrators have published
/// to it.
///
/// Members read here and never write, so nothing on this screen was posted by
/// another member. The loader is handed in already bound to this group, so the
/// screen cannot ask for any other group's posts.
@MainActor
struct GroupDetailView: View {
    let group: MemberGroup
    let loadPosts: @Sendable () async throws -> [MemberGroupPost]

    @State private var posts: [MemberGroupPost] = []
    @State private var isLoading = true
    @State private var failure: String?
    /// Only one recorded zikr plays at a time: a tapped video expands in place
    /// rather than every card loading a web view at once.
    @State private var playingVideoID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                if let meetingURL = group.meetingURL {
                    meetingCard(meetingURL)
                } else {
                    DICard {
                        Label("When the administrators arrange a meeting, its link appears here.", systemImage: "person.2.wave.2")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, DISpacing.lg)
                } else if let failure {
                    DICard {
                        VStack(alignment: .leading, spacing: DISpacing.sm) {
                            Text(failure).font(.subheadline)
                            Button("Try again") { Task { await load() } }
                                .buttonStyle(.bordered)
                        }
                    }
                } else if posts.isEmpty {
                    DICard {
                        Text("Nothing has been posted to this group yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(posts) { post in
                        postCard(post)
                    }
                }
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .diPageHeading(LocalizedStringKey(group.name))
        .task { await load() }
        .refreshable { await load() }
    }

    private func meetingCard(_ url: URL) -> some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                DISectionHeader(titleKey: "Meeting", systemImage: "person.2.wave.2")
                if let note = group.meetingNote {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                // Meetings are held on the platform the silsila already uses, so
                // this opens that app or site rather than dialling in-app.
                Link(destination: url) {
                    Label("Join the meeting", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func postCard(_ post: MemberGroupPost) -> some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                HStack(spacing: DISpacing.sm) {
                    Image(systemName: post.kind == .zikr ? "waveform" : "megaphone")
                        .foregroundStyle(DIColor.accent)
                    Text(post.title)
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                Text(post.publishedAt, format: .dateTime.day().month(.wide).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let body = post.body {
                    Text(body)
                        .font(.subheadline)
                }
                if let videoID = post.youtubeVideoID {
                    if playingVideoID == videoID {
                        YouTubePlayerView(videoID: videoID)
                            .frame(height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: DIRadius.md, style: .continuous))
                    } else {
                        Button {
                            playingVideoID = videoID
                            DIHaptics.light()
                        } label: {
                            Label("Play the recorded zikr", systemImage: "play.circle.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if let linkURL = post.linkURL {
                    Link(destination: linkURL) {
                        Label("Open link", systemImage: "arrow.up.right.square")
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        failure = nil
        do {
            posts = try await loadPosts()
        } catch {
            failure = error.localizedDescription
        }
        isLoading = false
    }
}
