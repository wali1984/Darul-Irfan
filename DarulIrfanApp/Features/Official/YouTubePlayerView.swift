import SwiftUI
import WebKit

struct YouTubePlayerSheet: View {
    let videoID: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            YouTubePlayerView(videoID: videoID)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

/// Where a group's shared playback stands, for a past video played to the
/// group: `position` seconds in at `at`, unless paused.
struct YouTubeSync: Equatable {
    var position: Double
    var paused: Bool
    var at: Date
}

struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    /// For a past video played to a group: the group's place. Playback joins
    /// the group there, and follows the admin's pauses and moves.
    var sync: YouTubeSync? = nil

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.accessibilityLabel = String(localized: "Video player")
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedVideoID != videoID else {
            // Same video: pass on a pause, resume or move by the admin.
            if let sync, sync != context.coordinator.sync {
                context.coordinator.sync = sync
                webView.evaluateJavaScript("window.setSync && window.setSync(\(Self.script(sync)))")
            }
            return
        }
        context.coordinator.loadedVideoID = videoID
        context.coordinator.sync = sync
        let safeID = videoID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let html: String
        if let sync {
            // Opens near the group's place; on play it moves to exactly where
            // the group is then. Without the player script it still opens
            // near the right place.
            let start = max(0, Int(sync.paused ? sync.position : sync.position + Date().timeIntervalSince(sync.at)))
            html = """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
            <style>html,body,iframe{width:100%;height:100%;margin:0;border:0;background:#000;overflow:hidden}</style></head>
            <body><iframe id="player" title="YouTube player" src="https://www.youtube-nocookie.com/embed/\(safeID)?playsinline=1&rel=0&enablejsapi=1&start=\(start)&origin=https://www.youtube-nocookie.com" allow="encrypted-media; picture-in-picture" allowfullscreen></iframe>
            <script>
            var player = null, ready = false, joined = false;
            var group = { pos: \(sync.position), paused: \(sync.paused), at: \(sync.at.timeIntervalSince1970) };
            function place() { return group.paused ? group.pos : group.pos + (Date.now() / 1000 - group.at); }
            function follow() {
              if (!ready) return;
              var state = player.getPlayerState();
              if (group.paused) { if (state === YT.PlayerState.PLAYING) player.pauseVideo(); return; }
              if (state === YT.PlayerState.PLAYING && Math.abs(player.getCurrentTime() - place()) > 5) player.seekTo(place(), true);
            }
            window.setSync = function (pos, paused, at) {
              var wasPaused = group.paused;
              group = { pos: pos, paused: paused, at: at };
              follow();
              if (wasPaused && !paused && joined && ready) { player.seekTo(place(), true); player.playVideo(); }
            };
            function onYouTubeIframeAPIReady() {
              player = new YT.Player("player", { events: {
                onReady: function () { ready = true; },
                onStateChange: function (e) {
                  if (e.data !== YT.PlayerState.PLAYING) return;
                  joined = true;
                  if (group.paused) { player.pauseVideo(); return; }
                  if (Math.abs(player.getCurrentTime() - place()) > 5) player.seekTo(place(), true);
                }
              } });
            }
            </script><script src="https://www.youtube.com/iframe_api"></script></body></html>
            """
        } else {
            html = """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
            <style>html,body,iframe{width:100%;height:100%;margin:0;border:0;background:#000;overflow:hidden}</style></head>
            <body><iframe title="YouTube player" src="https://www.youtube-nocookie.com/embed/\(safeID)?playsinline=1&rel=0" allow="encrypted-media; picture-in-picture" allowfullscreen></iframe></body></html>
            """
        }
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
    }

    private static func script(_ sync: YouTubeSync) -> String {
        "\(sync.position), \(sync.paused), \(sync.at.timeIntervalSince1970)"
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedVideoID: String?
        var sync: YouTubeSync?
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "about" || url.scheme == "data" { decisionHandler(.allow); return }
            guard let host = url.host?.lowercased() else { decisionHandler(.cancel); return }
            let allowed = host == "www.youtube-nocookie.com" || host == "youtube-nocookie.com"
                || host.hasSuffix(".googlevideo.com") || host.hasSuffix(".ytimg.com")
            decisionHandler(allowed ? .allow : .cancel)
        }
    }
}
