import Foundation
import Observation

@MainActor
protocol HalqaSessionTransport: AnyObject {
    func initialize(completion: @escaping (Bool) -> Void)
    func join(completion: @escaping (Bool) -> Void)
    func release(completion: @escaping (Bool) -> Void)
}

/// Owns a connection independently of a presenting screen. A different room
/// cannot replace a live or releasing connection; the user must leave first.
@MainActor
@Observable
final class HalqaSessionLifecycle {
    enum Phase { case idle, initializing, joining, joined, leaving, failed }
    private(set) var phase: Phase = .idle
    private(set) var sessionID: String?
    private var transport: (any HalqaSessionTransport)?
    private var generation = 0

    @discardableResult
    func start(sessionID: String, makeTransport: () -> any HalqaSessionTransport) -> Bool {
        if transport != nil {
            return self.sessionID == sessionID && [.initializing, .joining, .joined].contains(phase)
        }
        generation += 1
        let ticket = generation
        let connection = makeTransport()
        transport = connection
        self.sessionID = sessionID
        phase = .initializing
        connection.initialize { [weak self] success in
            guard let self, self.generation == ticket, self.phase == .initializing else { return }
            guard success else { self.close(failed: true); return }
            self.phase = .joining
            connection.join { [weak self] joined in
                guard let self, self.generation == ticket, self.phase == .joining else { return }
                if joined { self.phase = .joined } else { self.close(failed: true) }
            }
        }
        return true
    }

    func leave() { close(failed: false) }

    private func close(failed: Bool) {
        guard let connection = transport, phase != .leaving else { return }
        generation += 1 // Late init/join callbacks must never reconnect after Leave.
        let ticket = generation
        phase = .leaving
        connection.release { [weak self] released in
            guard let self, self.generation == ticket else { return }
            if released {
                self.transport = nil
                self.sessionID = nil
            }
            // Retain a failed release so another room cannot create a duplicate
            // connection. Leave may be retried explicitly.
            self.phase = failed || !released ? .failed : .idle
        }
    }
}
