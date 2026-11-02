import SwiftUI
import RealtimeKit

/// Presents the SDK-owned renderer. Removing this view detaches rendering only;
/// the retained connection continues audio until the user explicitly leaves.
@MainActor
struct NativeMeetingVideo: UIViewRepresentable {
    let participant: RtkMeetingParticipant
    var screenShare = false
    let revision: Int

    func makeUIView(context: Context) -> NativeMeetingVideoContainer {
        NativeMeetingVideoContainer()
    }

    func updateUIView(_ container: NativeMeetingVideoContainer, context: Context) {
        container.display(screenShare ? participant.getScreenShareVideoView() : participant.getVideoView())
    }

    static func dismantleUIView(_ container: NativeMeetingVideoContainer, coordinator: ()) {
        container.display(nil)
    }
}

@MainActor
final class NativeMeetingVideoContainer: UIView {
    private weak var displayed: UIView?

    func display(_ content: UIView?) {
        guard displayed !== content else { return }
        if displayed?.superview === self { displayed?.removeFromSuperview() }
        displayed = nil
        guard let content else { return }
        // The SDK caches one renderer. Transfer it when the screen is recreated;
        // old-container cleanup checks ownership and cannot detach the new host.
        content.removeFromSuperview()
        content.frame = bounds
        content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(content)
        displayed = content
    }
}
