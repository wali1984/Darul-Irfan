import Foundation

@MainActor
enum RecitationAudioHandoff {
    /// Main-actor players are paused directly. Posting an audio notification
    /// is insufficient because its observers may pause on a later task turn.
    static func prepare(audioPlayer: any AudioPlayerServicing, allowedNow: () -> Bool,
                        completion: (Bool) -> Void) {
        guard allowedNow(), NativeHalqaSession.shared.lifecycle.transport == nil else {
            completion(false)
            return
        }
        HifzPlayer.active?.pause()
        QuranListenPlayer.shared.stop()
        TranslationSpeaker.stopActive()
        audioPlayer.pauseForRecitation()
        completion(allowedNow() && NativeHalqaSession.shared.lifecycle.transport == nil)
    }
}
