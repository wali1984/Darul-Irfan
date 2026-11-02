import AVFoundation
import SwiftUI
import WebKit

/// A group meeting or joined zikr, inside the app.
///
/// The room page is Darul Irfan's own (served by its backend), loaded in a web
/// view with the participant pass in the URL fragment - which is never sent to
/// any server, so it stays out of every log. Camera and microphone are asked
/// for only here, and only when the person joins.
@MainActor
struct MeetingRoomView: View {
    let pass: GroupRoomPass
    @State private var rendererFailed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if rendererFailed {
                    Text("Could not complete action")
                        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                        .diScreenBackground()
                } else {
                    MeetingWebView(url: roomURL, onLeave: { dismiss() }, onFailure: { rendererFailed = true })
                }
            }
                .ignoresSafeArea(edges: .bottom)
                .background(Color(red: 0.04, green: 0.17, blue: 0.13))
                .navigationTitle("Darul Irfan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(DIColor.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Leave") { dismiss() }
                            .buttonStyle(DICompactButtonStyle())
                    }
                }
        }
    }

    /// The room page on the same backend the app already talks to - not the
    /// address the server reports, which may be a domain not yet live.
    private var roomURL: URL {
        let page = OfficialPlatformConfiguration.baseURL.appendingPathComponent("v1/meet")
        var components = URLComponents(url: page, resolvingAgainstBaseURL: false)
        components?.fragment = "token=\(pass.authToken)"
        return components?.url ?? page
    }
}

struct MeetingWebView: UIViewRepresentable {
    let url: URL
    let onLeave: () -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLeave: onLeave, onFailure: onFailure) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "darulirfan")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.accessibilityLabel = String(localized: "Meeting room")
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.active = false
        webView.uiDelegate = nil
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "darulirfan")
        webView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
        var active = true
        let onLeave: () -> Void
        let onFailure: () -> Void
        init(onLeave: @escaping () -> Void, onFailure: @escaping () -> Void) {
            self.onLeave = onLeave; self.onFailure = onFailure
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard active else { return }
            active = false
            onFailure()
        }

        /// Camera and microphone for the room page only; the system still asks
        /// the person the first time.
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            let ours = active && frame.isMainFrame && MeetingOrigin.allows(
                scheme: origin.protocol, host: origin.host, port: origin.port,
                trusted: OfficialPlatformConfiguration.baseURL
            )
            decisionHandler(ours ? .grant : .deny)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard active else { decisionHandler(.cancel); return }
            if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
            decisionHandler(MeetingOrigin.allows(action.request.url, trusted: OfficialPlatformConfiguration.baseURL) ? .allow : .cancel)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            let origin = message.frameInfo.securityOrigin
            guard active, message.frameInfo.isMainFrame, message.body as? String == "left",
                  MeetingOrigin.allows(scheme: origin.protocol, host: origin.host, port: origin.port,
                                       trusted: OfficialPlatformConfiguration.baseURL) else { return }
            DispatchQueue.main.async { if self.active { self.onLeave() } }
        }
    }
}
