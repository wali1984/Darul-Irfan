import SwiftUI

/// The Silsila's organisation for the Markaz's officers: totals, what is
/// live now, each region's Halqahs with their admins, and the announcements
/// sent to them. The Super admin also places each Halqah in a region and
/// brings the Halqah admins into the Silsila Markaz.
@MainActor
struct MarkazOrganisationView: View {
    let service: MemberGroupService
    let access: MarkazAccess

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @State private var organization: MarkazOrganization?
    @State private var announcements: [MarkazAnnouncement] = []
    @State private var loading = false
    @State private var failure: String?
    @State private var collapsed: Set<String> = []
    @State private var editing: MarkazHalqahPlace?
    @State private var announcing = false
    @State private var confirmingSync = false
    @State private var working = false
    @State private var message: String?

    private var markaz: MarkazService { MarkazService(groups: service) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DISpacing.lg) {
                if let organization {
                    totals(organization)
                        .diAppear()
                    actions
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    if let failure {
                        MarkazStateCard(failure: failure, loading: loading) { Task { await load() } }
                    }
                    if !organization.liveNow.isEmpty { liveNow(organization.liveNow) }
                    ForEach(organization.regions) { region in
                        regionSection(id: region.name, title: Text(verbatim: region.name.isEmpty ? String(localized: "Region") : region.name),
                                      region: region.name, halqahs: region.halqahs)
                    }
                    if !organization.unassigned.isEmpty {
                        regionSection(id: "\u{0}unassigned", title: Text("Not in a region yet"), region: nil,
                                      halqahs: organization.unassigned)
                    }
                    announcementsSection
                } else {
                    MarkazStateCard(failure: failure, loading: loading || failure == nil) { Task { await load() } }
                }
            }
            .padding(DISpacing.md)
            .diResponsiveWidth()
        }
        .diScreenBackground()
        .navigationTitle("Organisation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DIColor.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .task { await load() }
        .refreshable { await Task { await load() }.value }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { place in
            NavigationStack {
                MarkazHalqahPlaceEditor(service: service, place: place, regions: regionNames)
            }
        }
        .sheet(isPresented: $announcing, onDismiss: { Task { await load() } }) {
            NavigationStack {
                MarkazAnnounceView(service: service, regions: regionNames, halqahs: organization?.allHalqahs ?? [])
            }
        }
        .confirmationDialog("Bring in Halqah admins?", isPresented: $confirmingSync, titleVisibility: .visible) {
            Button("Bring them in") { Task { await syncAdmins() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every Halqah Administrator and Admin joins the Silsila Markaz as a member, so admin meetings and notices reach them. No one's role there is lowered.")
        }
        .alert("Silsila Markaz", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(verbatim: message ?? "") }
    }

    private var regionNames: [String] {
        (organization?.regions ?? []).map(\.name).filter { !$0.isEmpty }
    }

    // MARK: Parts

    private func totals(_ organization: MarkazOrganization) -> some View {
        HalqahGlassHeader(isLive: !organization.liveNow.isEmpty) {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Silsila Naqshbandia Owaisiah")
                    .diInterfaceFont(.caption, weight: .semibold)
                    .foregroundStyle(DIColor.goldGlow)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DISpacing.sm) { totalStats(organization.totals) }
                    VStack(spacing: DISpacing.sm) {
                        HStack(spacing: DISpacing.sm) {
                            HalqahStat(value: organization.totals.halqahs, labelKey: "Halqahs", systemImage: "person.3.fill")
                            HalqahStat(value: organization.totals.members, labelKey: "Members", systemImage: "person.fill")
                        }
                        HStack(spacing: DISpacing.sm) {
                            HalqahStat(value: organization.totals.administrators, labelKey: "Administrators", systemImage: "shield.lefthalf.filled")
                            HalqahStat(value: organization.totals.admins, labelKey: "Admins", systemImage: "key.fill")
                        }
                    }
                }
                if let markaz = organization.markaz {
                    Text("Silsila Markaz: \(markaz.members) members, \(markaz.officers) officers")
                        .diInterfaceFont(.footnote)
                        .foregroundStyle(Color.white.opacity(0.82))
                }
            }
        }
    }

    @ViewBuilder
    private func totalStats(_ totals: MarkazOrgTotals) -> some View {
        HalqahStat(value: totals.halqahs, labelKey: "Halqahs", systemImage: "person.3.fill")
        HalqahStat(value: totals.members, labelKey: "Members", systemImage: "person.fill")
        HalqahStat(value: totals.administrators, labelKey: "Administrators", systemImage: "shield.lefthalf.filled")
        HalqahStat(value: totals.admins, labelKey: "Admins", systemImage: "key.fill")
    }

    private var actions: some View {
        VStack(spacing: DISpacing.sm) {
            Button {
                announcing = true
            } label: {
                HalqahTileLabel(
                    titleKey: "Announce to Halqahs",
                    subtitle: Text("A notice to members or to the Halqah admins"),
                    systemImage: "megaphone.fill",
                    tint: DIColor.accent,
                    axis: .horizontal
                )
            }
            .buttonStyle(HalqahTileButtonStyle())
            .halqahTileAccessibility(titleKey: "Announce to Halqahs",
                                     value: Text("A notice to members or to the Halqah admins"),
                                     hintKey: "Opens a new announcement.")
            if access.isSuperAdmin {
                Button {
                    confirmingSync = true
                } label: {
                    HalqahTileLabel(
                        titleKey: "Bring in Halqah admins",
                        subtitle: Text("Adds every Halqah's admins to the Silsila Markaz"),
                        systemImage: "person.badge.shield.checkmark.fill",
                        axis: .horizontal
                    )
                }
                .buttonStyle(HalqahTileButtonStyle())
                .disabled(working)
                .halqahTileAccessibility(titleKey: "Bring in Halqah admins",
                                         value: Text("Adds every Halqah's admins to the Silsila Markaz"),
                                         hintKey: nil)
            }
        }
    }

    private func liveNow(_ live: [MarkazLiveNow]) -> some View {
        MarkazCard(titleKey: "Live now", systemImage: "dot.radiowaves.left.and.right", tint: DIColor.danger) {
            ForEach(live) { session in
                HStack(spacing: DISpacing.sm) {
                    DILivePulse(color: Color(hex: 0xFF5C5C), size: 8)
                    MarkazRow(title: session.name,
                              detail: liveLine(session),
                              value: String(localized: "\(session.listening) listening"))
                }
            }
        }
    }

    private func liveLine(_ session: MarkazLiveNow) -> String {
        var parts = [session.kind == "meeting" ? String(localized: "Meeting") : String(localized: "Zikr")]
        if let start = session.startedAt {
            parts.append(String(localized: "Since \(GroupInvitationDate.clock(start, locale: locale))"))
        }
        return parts.joined(separator: " \u{00b7} ")
    }

    private func regionSection(id: String, title: Text, region: String?, halqahs: [MarkazOrgHalqah]) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { !collapsed.contains(id) },
            set: { open in if open { collapsed.remove(id) } else { collapsed.insert(id) } }
        )) {
            VStack(spacing: DISpacing.sm) {
                ForEach(halqahs) { halqah in
                    if access.isSuperAdmin {
                        Button {
                            editing = MarkazHalqahPlace(halqah: halqah, region: region)
                        } label: {
                            MarkazHalqahCard(halqah: halqah, editable: true)
                        }
                        .buttonStyle(HalqahTileButtonStyle())
                        .accessibilityHint(Text("Sets its region, country and city."))
                    } else {
                        MarkazHalqahCard(halqah: halqah, editable: false)
                    }
                }
            }
            .padding(.top, DISpacing.sm)
        } label: {
            HStack(spacing: DISpacing.sm) {
                title
                    .diInterfaceFont(.headline, design: .serif)
                    .foregroundStyle(DIColor.textPrimary)
                Text(verbatim: "\(halqahs.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(HalqahInk.goldText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(DIColor.accent.opacity(0.15)))
            }
            .frame(minHeight: 44)
        }
        .tint(DIColor.primary)
    }

    @ViewBuilder
    private var announcementsSection: some View {
        MarkazCard(titleKey: "Past announcements", systemImage: "megaphone") {
            if announcements.isEmpty {
                Text("No announcements yet.")
                    .diInterfaceFont(.subheadline)
                    .foregroundStyle(DIColor.textMuted)
            }
            ForEach(announcements) { announcement in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: announcement.title)
                        .diInterfaceFont(.subheadline, weight: .semibold)
                        .foregroundStyle(DIColor.textPrimary)
                    if let text = announcement.body, !text.isEmpty {
                        Text(verbatim: text)
                            .diInterfaceFont(.footnote)
                            .foregroundStyle(DIColor.textPrimary.opacity(0.85))
                            .lineLimit(4)
                    }
                    Text(verbatim: announcementLine(announcement))
                        .diInterfaceFont(.caption)
                        .foregroundStyle(DIColor.textMuted)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                HalqahRowDivider()
            }
        }
    }

    private func announcementLine(_ announcement: MarkazAnnouncement) -> String {
        var parts: [String] = []
        parts.append(announcement.audience == "admins" ? String(localized: "To Halqah admins") : String(localized: "To members"))
        if !announcement.targets.isEmpty { parts.append(announcement.targets.joined(separator: ", ")) }
        if let by = announcement.sentBy, !by.isEmpty { parts.append(by) }
        if let at = announcement.sentAt { parts.append(GroupInvitationDate.text(at, locale: locale, includesTime: true)) }
        return parts.joined(separator: " \u{00b7} ")
    }

    // MARK: Loading and actions

    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            organization = try await markaz.organization()
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { failure = MarkazText.loadFailure(error) }
            return
        }
        // The list of announcements is extra: the page stands without it.
        if let list = try? await markaz.announcements() { announcements = list }
    }

    private func syncAdmins() async {
        guard !working, access.isSuperAdmin else { return }
        working = true
        defer { working = false }
        do {
            let result = try await markaz.syncAdmins()
            message = String(localized: "\(result.added) admins brought in. The Silsila Markaz now has \(result.total) members.")
            await load()
        } catch is CancellationError {
            return
        } catch {
            message = MemberGroupError.actionDescription(for: error)
        }
    }
}

/// One Halqah on the Organisation page: its status, people and admins, and
/// its last session.
private struct MarkazHalqahCard: View {
    let halqah: MarkazOrgHalqah
    let editable: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: DISpacing.xs) {
            HStack(spacing: DISpacing.sm) {
                MarkazStatusDot(status: halqah.status)
                Text(LocalizedStringKey(halqah.name))
                    .diInterfaceFont(.headline)
                    .foregroundStyle(DIColor.textPrimary)
                if halqah.kind == "markaz" {
                    DIPillBadge(text: String(localized: "Markaz"), color: DIColor.accent, foreground: HalqahInk.goldText)
                }
                if halqah.isLive {
                    DILivePulse(color: Color(hex: 0xFF5C5C), size: 7)
                }
                Spacer(minLength: 0)
                if editable {
                    Image(systemName: "pencil")
                        .diInterfaceFont(.footnote, weight: .semibold)
                        .foregroundStyle(DIColor.textMuted)
                        .accessibilityHidden(true)
                }
            }
            if let place = placeLine, !place.isEmpty {
                Text(verbatim: place)
                    .diInterfaceFont(.caption, weight: .semibold)
                    .foregroundStyle(HalqahInk.goldText)
            }
            Text(verbatim: countsLine)
                .diInterfaceFont(.footnote)
                .foregroundStyle(DIColor.textMuted)
            if !halqah.administrators.isEmpty {
                Text(verbatim: String(localized: "Administrators") + ": " + halqah.administrators.joined(separator: ", "))
                    .diInterfaceFont(.footnote)
                    .foregroundStyle(DIColor.textPrimary)
            }
            if !halqah.admins.isEmpty {
                Text(verbatim: String(localized: "Admins") + ": " + halqah.admins.joined(separator: ", "))
                    .diInterfaceFont(.footnote)
                    .foregroundStyle(DIColor.textPrimary)
            }
            Text(verbatim: lastLine)
                .diInterfaceFont(.caption)
                .foregroundStyle(DIColor.textMuted)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .halqahCard()
        .accessibilityElement(children: .combine)
    }

    private var placeLine: String? {
        let parts = [halqah.city, MarkazText.country(halqah.countryCode, locale: locale)].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private var countsLine: String {
        [String(localized: "Members: \(halqah.members)"),
         String(localized: "Zikr times: \(halqah.zikrTimes)"),
         String(localized: "\(halqah.sessions30Days) sessions in 30 days")].joined(separator: " \u{00b7} ")
    }

    private var lastLine: String {
        guard let last = halqah.lastSessionAt else { return String(localized: "No session yet") }
        return String(localized: "Last session: \(GroupInvitationDate.text(last, locale: locale, includesTime: true))")
    }
}

// MARK: - Region, country and city

/// A Halqah being placed, with the region it is in now.
struct MarkazHalqahPlace: Identifiable {
    let halqah: MarkazOrgHalqah
    let region: String?
    var id: String { halqah.id }
}

@MainActor
struct MarkazHalqahPlaceEditor: View {
    let service: MemberGroupService
    let place: MarkazHalqahPlace
    let regions: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var region = ""
    @State private var country = ""
    @State private var city = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Region, for example North America", text: $region)
                if !regions.isEmpty {
                    Menu {
                        ForEach(regions, id: \.self) { name in
                            Button { region = name } label: { Text(verbatim: name) }
                        }
                    } label: {
                        Label("Choose a region", systemImage: "list.bullet")
                    }
                }
            } header: {
                Text("Region")
            } footer: {
                Text("Leave it empty to take the Halqah out of its region.")
            }
            .listRowBackground(DIColor.surface)
            Section("Place") {
                TextField("Country code, for example US", text: $country)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: country) { _, value in
                        let cleaned = String(value.uppercased().filter { $0.isASCII && $0.isLetter }.prefix(2))
                        if cleaned != value { country = cleaned }
                    }
                TextField("City (optional)", text: $city)
            }
            .listRowBackground(DIColor.surface)
            if let error {
                Section { Text(verbatim: error).foregroundStyle(DIColor.danger) }
                    .listRowBackground(DIColor.surface)
            }
            Section {
                Button("Save") { Task { await save() } }
                    .buttonStyle(DISecondaryButtonStyle())
                    .disabled(working || (!country.isEmpty && country.count != 2))
            }
            .listRowBackground(DIColor.surface)
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .navigationTitle(Text(verbatim: place.halqah.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(DIToolbarButtonStyle()) } }
        .onAppear {
            region = place.region ?? ""
            country = place.halqah.countryCode ?? ""
            city = place.halqah.city ?? ""
        }
    }

    private func save() async {
        guard !working else { return }
        working = true
        defer { working = false }
        func cleaned(_ text: String) -> String? {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        do {
            try await MarkazService(groups: service).updateHalqah(
                place.halqah.id, region: cleaned(region), countryCode: cleaned(country), city: cleaned(city)
            )
            dismiss()
        } catch {
            self.error = MemberGroupError.actionDescription(for: error)
        }
    }
}

// MARK: - Announce

/// A notice to the members of chosen Halqahs, or to their admins in the
/// Silsila Markaz.
@MainActor
struct MarkazAnnounceView: View {
    let service: MemberGroupService
    let regions: [String]
    let halqahs: [MarkazOrgHalqah]

    enum Audience: String, CaseIterable, Hashable {
        case members, admins
        var title: LocalizedStringKey {
            switch self {
            case .members: "Members"
            case .admins: "Halqah admins"
            }
        }
    }

    enum Reach: String, CaseIterable, Hashable {
        case all, region, chosen
        var title: LocalizedStringKey {
            switch self {
            case .all: "All Halqahs"
            case .region: "A region"
            case .chosen: "Chosen Halqahs"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var message = ""
    @State private var audience: Audience = .members
    @State private var reach: Reach = .all
    @State private var region = ""
    @State private var chosen: Set<String> = []
    @State private var notify = true
    @State private var working = false
    @State private var error: String?
    @State private var result: MarkazAnnounceResult?

    private var ready: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch reach {
        case .all: return true
        case .region: return !region.isEmpty
        case .chosen: return !chosen.isEmpty
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                TextField("Message", text: $message, axis: .vertical)
                    .lineLimit(3...10)
            }
            .listRowBackground(DIColor.surface)
            Section {
                Picker("Who it is for", selection: $audience) {
                    ForEach(Audience.allCases, id: \.self) { item in Text(item.title).tag(item) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Who it is for")
            } footer: {
                Text(audience == .members
                     ? "Posted in each chosen Halqah, where its members read it."
                     : "The Halqah admins are brought into the Silsila Markaz first, and it is posted there.")
            }
            .listRowBackground(DIColor.surface)
            Section("Which Halqahs") {
                Picker("Which Halqahs", selection: $reach) {
                    ForEach(Reach.allCases, id: \.self) { item in Text(item.title).tag(item) }
                }
                if reach == .region {
                    Picker("Region", selection: $region) {
                        Text("Choose").tag("")
                        ForEach(regions, id: \.self) { name in Text(verbatim: name).tag(name) }
                    }
                }
                if reach == .chosen {
                    ForEach(halqahs) { halqah in
                        Toggle(isOn: Binding(
                            get: { chosen.contains(halqah.id) },
                            set: { on in if on { chosen.insert(halqah.id) } else { chosen.remove(halqah.id) } }
                        )) {
                            Text(LocalizedStringKey(halqah.name))
                        }
                    }
                }
            }
            .listRowBackground(DIColor.surface)
            Section {
                Toggle("Send a notification", isOn: $notify)
            }
            .listRowBackground(DIColor.surface)
            if let error {
                Section { Text(verbatim: error).foregroundStyle(DIColor.danger) }
                    .listRowBackground(DIColor.surface)
            }
            Section {
                Button {
                    Task { await send() }
                } label: {
                    if working { ProgressView() } else { Text("Send") }
                }
                .buttonStyle(DISecondaryButtonStyle())
                .disabled(working || !ready)
            }
            .listRowBackground(DIColor.surface)
        }
        .scrollContentBackground(.hidden)
        .diScreenBackground()
        .tint(DIColor.actionForeground)
        .toggleStyle(SwitchToggleStyle(tint: DIColor.primary))
        .navigationTitle("Announce to Halqahs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.buttonStyle(DIToolbarButtonStyle()) } }
        .alert("Sent", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil; dismiss() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let result {
                Text("Posted in \(result.posted) places. \(result.notified) people were notified.")
            }
        }
    }

    private func send() async {
        guard !working, ready else { return }
        working = true
        defer { working = false }
        let scope: String
        switch reach {
        case .all: scope = "all"
        case .region: scope = "region:" + region
        case .chosen: scope = "halqahs"
        }
        do {
            result = try await MarkazService(groups: service).announce(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: message.trimmingCharacters(in: .whitespacesAndNewlines),
                audience: audience.rawValue,
                scope: scope,
                halqahIDs: reach == .chosen ? Array(chosen) : [],
                notify: notify
            )
            error = nil
        } catch {
            self.error = MemberGroupError.actionDescription(for: error)
        }
    }
}
