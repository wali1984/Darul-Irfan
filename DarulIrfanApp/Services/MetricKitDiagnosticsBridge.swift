import Foundation
import MetricKit

/// Receives Apple's aggregated MetricKit payloads. Uploading remains disabled
/// until the user explicitly grants diagnostics consent in Settings.
final class MetricKitDiagnosticsBridge: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private let uploader: any DiagnosticsServicing

    init(uploader: any DiagnosticsServicing) {
        self.uploader = uploader
        super.init()
        MXMetricManager.shared.add(self)
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let data = payload.jsonRepresentation()
            Task { await uploader.uploadMetricPayload(data) }
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let data = payload.jsonRepresentation()
            Task { await uploader.uploadDiagnosticPayload(data) }
        }
    }
}
