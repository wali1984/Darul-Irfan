import SwiftUI

/// The biography of a narrator in a hadith's chain, shown as a native sheet when
/// a green narrator name is tapped. Reads only from our bundled store — never
/// calls out to any site. Dismiss returns the reader exactly where it was.
///
/// Bilingual by design: the Arabic is always shown, paired with English or Urdu
/// to match the reader's language.
@MainActor
struct NarratorBioSheet: View {
    let narratorId: Int
    let repository: any HadithRepositoryProtocol
    let appState: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var narrator: HadithNarrator?
    @State private var isLoading = true
    @State private var failed = false
    @State private var attempt = 0

    /// The content language: "System" on an Urdu phone reads in Urdu.
    private var languageCode: String { appState.settings.language.contentLanguageCode }
    private var fontScale: Double { appState.settings.readerFontScale.rawValue }
    private var isUrdu: Bool { languageCode == "ur" }

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(DISpacing.xl)
                } else if failed {
                    DICard {
                        VStack(alignment: .leading, spacing: DISpacing.sm) {
                            Text("The biography could not be loaded. Please try again.")
                                .diInterfaceFont(.body)
                                .foregroundStyle(DIColor.danger)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Retry") { attempt += 1 }
                                .buttonStyle(DISecondaryButtonStyle())
                        }
                    }
                    .padding(DISpacing.md)
                } else if let narrator {
                    content(narrator)
                        .padding(DISpacing.md)
                        .diResponsiveWidth()
                } else {
                    // Some narrators in the chains have no biography at the
                    // source either (it has no page for them), so none is on
                    // its way: say only that there is none.
                    DIEmptyState(
                        systemImage: "person.crop.circle.badge.questionmark",
                        titleKey: "No biography is available for this narrator."
                    )
                    .padding(DISpacing.xl)
                }
            }
            .diScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: "\(narratorId)-\(attempt)") {
            isLoading = true
            failed = false
            do {
                let loaded = try await repository.narrator(id: narratorId)
                guard !Task.isCancelled else { return }
                narrator = loaded
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
            isLoading = false
        }
    }

    @ViewBuilder
    private func content(_ n: HadithNarrator) -> some View {
        VStack(alignment: .leading, spacing: DISpacing.md) {
            // Names: Arabic in the Quran face, then the reader-language name.
            VStack(alignment: .leading, spacing: DISpacing.xs) {
                if let ar = n.nameArabic, !ar.isEmpty {
                    Text(verbatim: ar)
                        .font(DIFont.quranArabic(scale: fontScale * 0.9))
                        .foregroundStyle(DIColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                let localname = n.name(languageCode: languageCode)
                Text(verbatim: localname)
                    .diInterfaceFont(.title2, weight: .semibold, design: .serif)
                    .foregroundStyle(DIColor.textPrimary)
            }

            // Quick facts.
            let facts = factRows(n)
            if !facts.isEmpty {
                DICard {
                    VStack(alignment: .leading, spacing: DISpacing.xs) {
                        ForEach(facts, id: \.0) { label, value in
                            HStack(alignment: .top, spacing: DISpacing.sm) {
                                Text(label)
                                    .diInterfaceFont(.caption, weight: .semibold)
                                    .foregroundStyle(DIColor.textMuted)
                                    .frame(width: 96, alignment: .leading)
                                Text(verbatim: value)
                                    .diInterfaceFont(.subheadline)
                                    .foregroundStyle(DIColor.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            // Long-form biography in the reader's language where there is
            // one; otherwise the source's short description.
            if let bio = isUrdu ? n.bioUrdu : n.bioEnglish, !bio.isEmpty {
                sectionTitle("Biography")
                localizedProse(bio)
            } else if let desc = isUrdu ? (n.descriptionUrdu ?? n.descriptionArabic) : n.descriptionEnglish,
                      !desc.isEmpty {
                sectionTitle("Description")
                localizedProse(desc)
            }

            // Scholarly appraisals (jarḥ wa-taʿdīl): the Arabic, then its
            // English or Urdu.
            let appraisals = publishedAppraisals(n)
            if !appraisals.isEmpty {
                sectionTitle("Scholarly appraisals")
                ForEach(Array(appraisals.enumerated()), id: \.offset) { _, a in
                    DICard {
                        VStack(alignment: .leading, spacing: DISpacing.xs) {
                            if let who = a.scholarName(languageCode: languageCode) {
                                Text(verbatim: who)
                                    .diInterfaceFont(.caption, weight: .semibold)
                                    .foregroundStyle(DIColor.accent)
                            }
                            if let ar = a.textArabic, !ar.isEmpty {
                                Text(verbatim: ar)
                                    .font(DIFont.quranArabic(scale: fontScale * 0.7))
                                    .foregroundStyle(DIColor.textPrimary)
                                    .environment(\.layoutDirection, .rightToLeft)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            if let tr = isUrdu ? a.textUrdu : a.textEnglish, !tr.isEmpty {
                                localizedProse(tr)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Appraisals worth rendering: those that carry the scholar's words. A
    /// row with a name and no body would draw an empty card.
    ///
    /// The Arabic is shown to every reader, in the Quran face under the
    /// scholar's name, with its English or Urdu beneath it.
    private func publishedAppraisals(_ narrator: HadithNarrator) -> [NarratorAppraisal] {
        (narrator.appraisals ?? []).filter { appraisal in
            let arabic = appraisal.textArabic?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let translated = (isUrdu ? appraisal.textUrdu : appraisal.textEnglish)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !arabic.isEmpty || !translated.isEmpty
        }
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .diInterfaceFont(.headline, design: .serif)
            .foregroundStyle(DIColor.textPrimary)
            .padding(.top, DISpacing.xs)
    }

    /// Prose in the reader's language, in the right script and direction.
    @ViewBuilder
    private func localizedProse(_ text: String) -> some View {
        if isUrdu {
            Text(verbatim: text)
                .font(DIFont.urduBody(scale: fontScale))
                .foregroundStyle(DIColor.textPrimary)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(verbatim: text)
                .diInterfaceFont(.body)
                .foregroundStyle(DIColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Strictly per-language rows. In English UI every value is the English
    /// column; in Urdu UI the Urdu column, and the Arabic one only for a
    /// record that has no Urdu. A fact the record lacks is not shown.
    private func factRows(_ n: HadithNarrator) -> [(String, String)] {
        var rows: [(String, String)] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { rows.append((label, value)) }
        }
        if isUrdu {
            add(String(localized: "Grade"), n.gradeUrdu ?? n.gradeArabic)
            add(String(localized: "Byname"), n.bynameUrdu ?? n.bynameArabic)
            add(String(localized: "Kunya"), n.kunyaUrdu ?? n.kunyaArabic)
            add(String(localized: "Generation"), n.generationUrdu ?? n.generationArabic)
            add(String(localized: "Profession"), n.professionUrdu ?? n.professionArabic)
            add(String(localized: "School"), n.madhhabUrdu ?? n.madhhabArabic)
            add(String(localized: "Died"), n.deathYearArabic ?? n.deathYear)
            add(String(localized: "Cities"), n.citiesUrdu ?? n.citiesArabic)
            add(String(localized: "Affiliations"), n.affiliationsUrdu ?? n.affiliationsArabic)
            add(String(localized: "Lineage"), n.lineageUrdu ?? n.lineageArabic)
        } else {
            add(String(localized: "Grade"), n.gradeEnglish)
            add(String(localized: "Byname"), n.byname)
            add(String(localized: "Kunya"), n.kunya)
            add(String(localized: "Generation"), n.generation)
            add(String(localized: "Profession"), n.profession)
            add(String(localized: "School"), n.madhhab)
            add(String(localized: "Died"), n.deathYear)
            add(String(localized: "Cities"), n.cities)
            add(String(localized: "Affiliations"), n.affiliations)
            add(String(localized: "Lineage"), n.lineageEnglish)
        }
        if let count = n.hadithCount { add(String(localized: "Narrations"), "\(count)") }
        return rows
    }
}
