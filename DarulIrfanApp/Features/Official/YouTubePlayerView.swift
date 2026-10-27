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

struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    /// For a recording played to a group: when it started. Playback begins
    /// where the group is, even if the member presses play minutes later.
    var playsTogetherFrom: Date? = nil

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
        guard context.coordinator.loadedVideoID != videoID else { return }
        context.coordinator.loadedVideoID = videoID
        let safeID = videoID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let html: String
        if let playsTogetherFrom {
            // Starts near the group's place, then on first play jumps to where
            // the group is at that moment. Without the player script it still
            // starts near the right place.
            let started = Int(playsTogetherFrom.timeIntervalSince1970)
            let start = max(0, Int(Date().timeIntervalSince(playsTogetherFrom)))
            html = """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
            <style>html,body,iframe{width:100%;height:100%;margin:0;border:0;background:#000;overflow:hidden}</style></head>
            <body><iframe id="player" title="YouTube player" src="https://www.youtube-nocookie.com/embed/\(safeID)?playsinline=1&rel=0&enablejsapi=1&start=\(start)&origin=https://www.youtube-nocookie.com" allow="encrypted-media; picture-in-picture" allowfullscreen></iframe>
            <script>
            var joined = false;
            function onYouTubeIframeAPIReady() {
              new YT.Player("player", { events: { onStateChange: function (e) {
                if (joined || e.data !== YT.PlayerState.PLAYING) return;
                joined = true;
                var at = Date.now() / 1000 - \(started);
                if (Math.abs(e.target.getCurrentTime() - at) > 5) e.target.seekTo(at, true);
              } } });
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

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedVideoID: String?
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
