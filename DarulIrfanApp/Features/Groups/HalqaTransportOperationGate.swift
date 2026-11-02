/// Serializes SDK initialization/join with release. A late success cannot
/// revive local controls or race a release that already reported completion.
@MainActor
final class HalqaTransportOperationGate {
    private var active = true
    private var pending = false
    private var deferredRelease: (() -> Void)?

    func begin() -> Bool {
        guard active, !pending else { return false }
        pending = true
        return true
    }

    func finish() -> Bool {
        pending = false
        let release = deferredRelease
        deferredRelease = nil
        release?()
        return active
    }

    func close(release: @escaping () -> Void) {
        active = false
        if pending { deferredRelease = release }
        else { release() }
    }
}
