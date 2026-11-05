import AVFoundation
import SwiftUI
import UIKit
import WebKit

/// Our Sheikh's live sound: what Paltalk or a broadcasting phone carries, in
/// the app (Android LiveAudio).
enum LiveAudioMode: String, Identifiable {
    /// Hear the Zikr as it happens.
    case listen
    /// An admin's phone sends its microphone to the app, Paltalk and YouTube.
    case broadcast

    var id: String { rawValue }

    /// The live service's page for this mode.
    var path: String { self == .listen ? "listen" : "host" }
}

enum LiveAudioConfiguration {
    /// The live service: the only origin the page may stay on, and the only
    /// one ever given the microphone.
    static let baseURL = URL(string: "https://darul-irfan-live-staging.wajidmahmoodali1984-e23.workers.dev")!

    /// The member's sign-in travels in the fragment, which is never sent to
    /// any server; the page trades it for the live service's own key at once
    /// and clears it from the address.
    static func pageURL(_ mode: LiveAudioMode, token: String, urdu: Bool) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(mode.path), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "lang", value: urdu ? "ur" : "en")]
        var fragment = CharacterSet.urlFragmentAllowed
        fragment.remove(charactersIn: "&=+#")
        let bearer = token.isEmpty ? "none" : token
        components?.percentEncodedFragment = "bearer=" + (bearer.addingPercentEncoding(withAllowedCharacters: fragment) ?? "none")
        return components?.url ?? baseURL
    }
}

@MainActor
struct LiveAudioView: View {
    let mode: LiveAudioMode
    let token: String
    let urdu: Bool
    @State private var rendererFailed = false
    @State private var previousCategory: AVAudioSession.Category?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if rendererFailed {
                    Text("Could not complete action")
                        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                        .diScreenBackground()
                } else {
                    LiveAudioWebView(url: LiveAudioConfiguration.pageURL(mode, token: token, urdu: urdu),
                                     allowsMicrophone: mode == .broadcast,
                                     onFailure: { rendererFailed = true })
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .background(Color(red: 0.04, green: 0.17, blue: 0.13))
            .navigationTitle(mode == .listen ? Text("Listen live") : Text("Broadcast"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DIColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .buttonStyle(DICompactButtonStyle())
                }
            }
        }
        .onAppear(perform: claimAudio)
        .onDisappear(perform: releaseAudio)
    }

    /// The Zikr plays even with the ring switch on silent; broadcasting also
    /// records. The app's own setting comes back when this closes.
    private func claimAudio() {
        UIApplication.shared.isIdleTimerDisabled = true
        let audio = AVAudioSession.sharedInstance()
        previousCategory = audio.category
        if mode == .broadcast {
            try? audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        } else {
            try? audio.setCategory(.playback, mode: .spokenAudio)
        }
        try? audio.setActive(true)
    }

    private func releaseAudio() {
        UIApplication.shared.isIdleTimerDisabled = false
        let audio = AVAudioSession.sharedInstance()
        try? audio.setActive(false, options: .notifyOthersOnDeactivation)
        if let previousCategory { try? audio.setCategory(previousCategory) }
    }
}

struct LiveAudioWebView: UIViewRepresentable {
    let url: URL
    let allowsMicrophone: Bool
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(allowsMicrophone: allowsMicrophone, onFailure: onFailure) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Nothing the page keeps (its key) outlives this screen.
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.accessibilityLabel = String(localized: "Live audio")
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.active = false
        webView.uiDelegate = nil
        webView.navigationDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        var active = true
        let allowsMicrophone: Bool
        let onFailure: () -> Void
        init(allowsMicrophone: Bool, onFailure: @escaping () -> Void) {
            self.allowsMicrophone = allowsMicrophone; self.onFailure = onFailure
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard active else { return }
            active = false
            onFailure()
        }

        /// The microphone only for the broadcast page of the live service;
        /// never the camera. The system still asks the person the first time.
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            let ours = active && allowsMicrophone && type == .microphone && frame.isMainFrame && MeetingOrigin.allows(
                scheme: origin.protocol, host: origin.host, port: origin.port, trusted: LiveAudioConfiguration.baseURL
            )
            decisionHandler(ours ? .grant : .deny)
        }

        /// The page stays on the live service; any other address opens
        /// outside the app.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard active else { decisionHandler(.cancel); return }
            if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
            if MeetingOrigin.allows(action.request.url, trusted: LiveAudioConfiguration.baseURL) {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            if let address = action.request.url, address.scheme == "https" {
                DispatchQueue.main.async { UIApplication.shared.open(address) }
            }
        }
    }
}
