import RealtimeKit

/// Shared entry policy for the native Halqa migration. A participant's server
/// role controls publishing rights; joining never implicitly enables capture.
@MainActor
enum NativeMeetingConfiguration {
    static func makeClient() -> RealtimeKitClient {
        RealtimeKitiOSClientBuilder().build()
    }

    static func meetingInfo(authToken: String) -> RtkMeetingInfo {
        RtkMeetingInfo(authToken: authToken, enableAudio: false, enableVideo: false)
    }
}
