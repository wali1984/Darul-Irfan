import Foundation

enum DailyZikrBanner {
    static let title = "Daily Zikr with Sheikh-ul-Mukarram Hazrat Abdul Qadeer Awan MZA"
    enum Phase: Equatable { case upcoming, live }
    static func phase(start: Date, end: Date, now: Date) -> Phase? {
        if now < start.addingTimeInterval(-1800) || now >= end { return nil }
        return now < start ? .upcoming : .live
    }
}
