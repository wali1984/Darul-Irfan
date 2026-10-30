import Foundation
import XCTest
@testable import DarulIrfan

/// The October 2026 redesign of the Halqah tab: every setting in one list,
/// Language first; the Silsila's pages; and one Notifications screen that
/// gathers the reminders and notices offered elsewhere, under the very same
/// keys and with the very same effect on the saved settings.
final class HalqahRedesignTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "HalqahRedesignTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Settings

    func testSettingsListLanguageFirstInTheBriefsOrder() {
        XCTAssertEqual(SettingsEntry.allCases.first, .language)
        XCTAssertEqual(SettingsEntry.allCases.map(\.title), [
            "Language",
            "Location",
            "Prayer calculation",
            "Notifications",
            "Appearance",
            "Hijri Calendar",
            "Content & Storage",
            "Privacy",
            "Licences",
        ])
    }

    /// Notifications, which gathers every alert, is the one gold row.
    func testOnlyNotificationsIsGold() {
        XCTAssertEqual(SettingsEntry.allCases.filter(\.isGold), [.notifications])
    }

    // MARK: - Silsila

    func testSilsilaRowsAreTheLibrarysAboutAndTeachingsPages() {
        XCTAssertEqual(
            SilsilaEntry.about.map(\.category),
            [.aboutSilsila, .sheikhAbdulQadeerAwan, .sheikhMuhammadAkramAwan, .shajra]
        )
        XCTAssertEqual(
            SilsilaEntry.teachings.map(\.category),
            [.tasawwuf, .tazkiyahNafs, .zikrAllah, .baiat, .methodOfZikr]
        )
        XCTAssertEqual(
            SilsilaEntry.teachings.map(\.title),
            ["Tasawwuf", "Tazkiyah-e-Nafs", "The Need for Zikr", "Bai'at", "Method of Zikr"]
        )
        let all = SilsilaEntry.about + SilsilaEntry.teachings
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "Each category has one row")
    }

    /// The honorifics stay with each Sheikh's name.
    func testTheSheikhsKeepTheirHonorifics() {
        XCTAssertEqual(SilsilaEntry.about[1].title, "Hazrat Ameer Abdul Qadeer Awan (MZA)")
        XCTAssertEqual(SilsilaEntry.about[2].title, "Hazrat Ameer Muhammad Akram Awan (RA)")
    }

    /// A category of one page opens it directly; no list of one.
    func testASilsilaRowOpensItsOnlyPageDirectly() {
        XCTAssertEqual(SilsilaOpening.forItems(withIDs: []), .empty)
        XCTAssertEqual(SilsilaOpening.forItems(withIDs: ["page-shajra"]), .item("page-shajra"))
        XCTAssertEqual(SilsilaOpening.forItems(withIDs: ["a", "b"]), .list)
    }

    // MARK: - Alert switches

    /// The Zikr tab's "Notify me when Daily Zikr goes live", as Settings now
    /// offers it too: on turns official alerts on with the live zikr topic,
    /// off drops only that topic.
    func testDailyZikrLiveSwitchChangesTheSettingsAsTheZikrTabDoes() {
        var settings = AppSettings()
        XCTAssertFalse(AlertSettingsRules.dailyZikrLiveIsOn(settings), "Official alerts start off")

        AlertSettingsRules.setDailyZikrLive(true, in: &settings)
        XCTAssertTrue(settings.push.isEnabled)
        XCTAssertTrue(settings.push.topics.contains(.liveZikr))
        XCTAssertEqual(settings.push.consentVersion, PushPreferences.currentConsentVersion)
        XCTAssertTrue(AlertSettingsRules.dailyZikrLiveIsOn(settings))

        let otherTopics = settings.push.topics.subtracting([.liveZikr])
        AlertSettingsRules.setDailyZikrLive(false, in: &settings)
        XCTAssertTrue(settings.push.isEnabled, "Turning it off leaves the other official alerts on")
        XCTAssertFalse(settings.push.topics.contains(.liveZikr))
        XCTAssertEqual(settings.push.topics, otherTopics)
        XCTAssertFalse(AlertSettingsRules.dailyZikrLiveIsOn(settings))
    }

    func testOfficialAlertsAndTopicsChangeOnlyTheirOwnSetting() {
        var settings = AppSettings()
        let topics = settings.push.topics

        AlertSettingsRules.setOfficialAlerts(true, in: &settings)
        XCTAssertTrue(settings.push.isEnabled)
        XCTAssertEqual(settings.push.topics, topics)
        XCTAssertEqual(settings.push.consentVersion, PushPreferences.currentConsentVersion)

        AlertSettingsRules.setTopic(.broadcasts, true, in: &settings)
        XCTAssertTrue(settings.push.topics.contains(.broadcasts))
        AlertSettingsRules.setTopic(.events, false, in: &settings)
        XCTAssertFalse(settings.push.topics.contains(.events))

        AlertSettingsRules.setOfficialAlerts(false, in: &settings)
        XCTAssertFalse(settings.push.isEnabled)
        XCTAssertFalse(AlertSettingsRules.dailyZikrLiveIsOn(settings), "Live zikr needs official alerts on")
    }

    // MARK: - Zikr reminders

    private func session(id: String, title: String, hour: Int, anchor: String? = nil) -> ZikrSession {
        ZikrSession(
            id: id,
            title: title,
            weekdays: Array(1...7),
            startHour: hour,
            startMinute: 0,
            durationMinutes: 30,
            timeZoneIdentifier: "Asia/Karachi",
            joinUrl: nil,
            instructions: nil,
            availabilityNote: nil,
            sourceUrl: nil,
            anchor: anchor,
            anchorOffsetMinutes: anchor == nil ? nil : 60
        )
    }

    /// Settings > Notifications reads and writes the Zikr tab's own keys.
    func testZikrRemindersUseTheZikrTabsKeys() {
        XCTAssertEqual(ZikrReminders.reminderID(forSession: "zikr-after-isha"), "zikrReminder.zikr-after-isha")
    }

    @MainActor
    func testAZikrReminderSwitchedOnInSettingsIsTheZikrTabsReminder() async {
        let daily = session(id: "zikr-after-isha", title: "Daily Zikr", hour: 21)
        let tahajjud = session(id: "zikr-tahajjud", title: "Tahajjud Zikr", hour: 4, anchor: "beforeFajr")
        defaults.set(true, forKey: "zikrReminder.zikr-after-isha")
        let notifications = RecordingNotifications()
        let model = ZikrReminderSettingsModel(notifications: notifications, calculator: nil, defaults: defaults)

        model.load(sessions: [daily, tahajjud])
        XCTAssertTrue(model.isOn(daily), "On in the Zikr tab, on here")
        XCTAssertFalse(model.isOn(tahajjud))

        await model.set(true, for: tahajjud)
        XCTAssertTrue(model.isOn(tahajjud))
        XCTAssertTrue(defaults.bool(forKey: "zikrReminder.zikr-tahajjud"))
        XCTAssertEqual(notifications.scheduled["zikrReminder.zikr-tahajjud"]?.count, ZikrReminders.occurrencesPerSession,
                       "A week of reminders, as the Zikr tab keeps")

        await model.set(false, for: daily)
        XCTAssertFalse(model.isOn(daily))
        XCTAssertFalse(defaults.bool(forKey: "zikrReminder.zikr-after-isha"))
        XCTAssertEqual(notifications.cancelled, ["zikrReminder.zikr-after-isha"])
        XCTAssertFalse(model.permissionDenied)
    }

    @MainActor
    func testAZikrReminderStaysOffWhenIOSRefuses() async {
        let daily = session(id: "zikr-after-isha", title: "Daily Zikr", hour: 21)
        let notifications = RecordingNotifications()
        notifications.granted = false
        let model = ZikrReminderSettingsModel(notifications: notifications, calculator: nil, defaults: defaults)
        model.load(sessions: [daily])

        await model.set(true, for: daily)

        XCTAssertFalse(model.isOn(daily))
        XCTAssertFalse(defaults.bool(forKey: "zikrReminder.zikr-after-isha"))
        XCTAssertTrue(notifications.scheduled.isEmpty)
        XCTAssertTrue(model.permissionDenied)
    }

    // MARK: - Event reminders

    private func event(id: String, start: Date?) -> CommunityEvent {
        CommunityEvent(
            id: id,
            kind: .other,
            title: id,
            titleUrdu: nil,
            details: nil,
            startDate: start,
            endDate: nil,
            datesAreApproximate: false,
            venue: nil,
            sourceUrl: nil,
            updatedAt: nil
        )
    }

    /// The reminders a program's page set ("eventReminder.<id>"), for
    /// programs still to come, soonest first.
    func testEventRemindersListTheProgramsWithAReminderStillToCome() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        let later = event(id: "later", start: now.addingTimeInterval(30 * day))
        let sooner = event(id: "sooner", start: now.addingTimeInterval(10 * day))
        let unset = event(id: "unset", start: now.addingTimeInterval(5 * day))
        let past = event(id: "past", start: now.addingTimeInterval(-10 * day))
        let undated = event(id: "undated", start: nil)
        for id in ["later", "sooner", "past", "undated"] {
            defaults.set(true, forKey: EventReminderList.key(forEvent: id))
        }

        let listed = EventReminderList.upcomingWithReminders(
            in: [later, past, unset, undated, sooner],
            defaults: defaults,
            now: now
        )

        XCTAssertEqual(listed.map(\.id), ["sooner", "later"])
        XCTAssertEqual(EventReminderList.key(forEvent: "salana-ijtema"), "eventReminder.salana-ijtema")
    }

    // MARK: - Halqah notices

    /// The switch shows what the Halqah page always showed.
    @MainActor
    func testHalqahNoticesSwitchState() {
        XCTAssertEqual(HalqahNoticesModel.shownStatus(turnedOff: false, permission: .allowed), .on)
        XCTAssertEqual(HalqahNoticesModel.shownStatus(turnedOff: false, permission: .notAsked), .off)
        XCTAssertEqual(HalqahNoticesModel.shownStatus(turnedOff: false, permission: .denied), .blocked)
        XCTAssertEqual(HalqahNoticesModel.shownStatus(turnedOff: true, permission: .allowed), .off)
        XCTAssertEqual(HalqahNoticesModel.shownStatus(turnedOff: true, permission: .denied), .off)
    }

    /// The account's controls show while signed in, including when the
    /// groups failed to load, so the member can still sign out or delete.
    @MainActor
    func testTheAccountShowsWhileSignedIn() {
        let model = GroupsModel()
        model.phase = .ready
        XCTAssertTrue(model.showsAccount)
        model.phase = .failed("offline")
        XCTAssertTrue(model.showsAccount)
        model.phase = .loading
        XCTAssertFalse(model.showsAccount)
        model.phase = .signedOut
        XCTAssertFalse(model.showsAccount)
    }
}

/// Records what is scheduled and cancelled, and answers the permission
/// request as told.
private final class RecordingNotifications: NotificationScheduling, @unchecked Sendable {
    var granted = true
    private(set) var scheduled: [String: [Date]] = [:]
    private(set) var cancelled: [String] = []

    func requestPermission() async -> Bool { granted }

    func reschedulePrayerNotifications(
        schedules: [PrayerDaySchedule],
        preferences: PrayerNotificationPreferences
    ) async {}

    func scheduleReminder(id: String, title: String, body: String, at date: Date) async {
        scheduled[id] = [date]
    }

    func scheduleReminders(id: String, title: String, body: String, at dates: [Date]) async {
        scheduled[id] = dates
    }

    func cancelReminder(id: String) async {
        cancelled.append(id)
    }

    func notificationsAllowed() async -> Bool { granted }

    func pendingCount() async -> Int { scheduled.count }
}
