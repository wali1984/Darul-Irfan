import SwiftUI

// A living gradient system so the app feels alive and shifts through the day —
// a reason to return morning to night. All gradients stay within the brand
// (emerald / forest / gold / warm charcoal) but change mood by time of day.

enum DIGradient {

    /// Phases of the day, each with its own mood.
    enum DayPhase {
        case dawn, morning, midday, afternoon, dusk, night

        static func current(_ date: Date = Date(), calendar: Calendar = .current) -> DayPhase {
            switch calendar.component(.hour, from: date) {
            case 4..<6: return .dawn
            case 6..<10: return .morning
            case 10..<15: return .midday
            case 15..<18: return .afternoon
            case 18..<20: return .dusk
            default: return .night
            }
        }
    }

    /// The hero background — a deep, layered, time-aware gradient. Emerald and
    /// forest anchor it; dawn/dusk warm it, night deepens it.
    static func hero(for date: Date = Date()) -> LinearGradient {
        let stops: [Color]
        switch DayPhase.current(date) {
        case .dawn:
            stops = [Color(hex: 0x1B2A4A), Color(hex: 0x0B6E4F), Color(hex: 0x011D16)]
        case .morning:
            stops = [Color(hex: 0x0E8A63), Color(hex: 0x0B6E4F), Color(hex: 0x011D16)]
        case .midday:
            stops = [Color(hex: 0x12946B), Color(hex: 0x0B6E4F), Color(hex: 0x011D16)]
        case .afternoon:
            stops = [Color(hex: 0x0B6E4F), Color(hex: 0x1E5E48), Color(hex: 0x011D16)]
        case .dusk:
            stops = [Color(hex: 0x8A5A22), Color(hex: 0x0B5B40), Color(hex: 0x011D16)]
        case .night:
            stops = [Color(hex: 0x0B4635), Color(hex: 0x011D16), Color(hex: 0x0B0B09)]
        }
        return LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// A warm radial glow to layer behind a focal element (the seal, hero).
    static let auraGold = RadialGradient(
        colors: [Color(hex: 0xFBCE54).opacity(0.35), Color.clear],
        center: .center, startRadius: 4, endRadius: 220
    )

    /// Emerald brand gradient for primary surfaces/buttons.
    static let emerald = LinearGradient(
        colors: [DIColor.primary, DIColor.primaryDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// A gold sheen used on accents, dividers, and the shimmer sweep.
    static let goldSheen = LinearGradient(
        colors: [Color(hex: 0xC6A253), Color(hex: 0xE9CE86), Color(hex: 0xC6A253)],
        startPoint: .leading, endPoint: .trailing
    )

    /// Subtle top-lit card gradient (adds life to a flat surface).
    static let cardSheen = LinearGradient(
        colors: [DIColor.surface, DIColor.surface.opacity(0.94)],
        startPoint: .top, endPoint: .bottom
    )

    /// A gentle greeting line for the phase of day.
    static func greeting(for date: Date = Date()) -> String {
        switch DayPhase.current(date) {
        case .dawn, .morning: return "Good morning"
        case .midday: return "Good afternoon"
        case .afternoon: return "Good afternoon"
        case .dusk: return "Good evening"
        case .night: return "Peaceful night"
        }
    }
}
