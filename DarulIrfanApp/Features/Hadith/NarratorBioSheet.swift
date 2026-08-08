import SwiftUI

/// The biography of a narrator in a hadith's chain, shown as a native sheet when
/// a green narrator name is tapped. Reads only from our bundled store — never
/// calls out to any site. Dismiss returns the reader exactly where it was.
///
/// Bilingual by design: the Arabic is always shown, paired with English or Urdu
/// to match the reader's language. Where a translation has not been prepared, it
/// says so plainly rather than showing fabricated text.
@MainActor
struct NarratorBioSheet: View {
    let narratorId: Int
    let repository: any HadithRepositoryProtocol
    let appState: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var narrator: HadithNarrator?
    @State private var isLoading = true

    private var languageCode: String { appState.settings.language.rawValue }
    private var fontScale: Double { appState.settings.readerFontScale.rawValue }
    private var isUrdu: Bool { languageCode == "ur" }

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(DISpacing.xl)
                } else if let narrator {
                    content(narrator)
                        .padding(DISpacing.md)
                        .diResponsiveWidth()
                } else {
                    DIEmptyState(
                        systemImage: "person.crop.circle.badge.questionmark",
                        titleKey: "Biography not available yet",
                        messageKey: "This narrator's biography will arrive with a future content update."
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
        .task {
            narrator = try? await repository.narrator(id: narratorId)
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
                        .environment(\.layoutDirection, .rightToLeft)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                let localname = n.name(languageCode: languageCode)
                Text(verbatim: localname)
                    .font(DIFont.heading)
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
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DIColor.textMuted)
                                    .frame(width: 96, alignment: .leading)
                                Text(verbatim: value)
                                    .font(.subheadline)
                                    .foregroundStyle(DIColor.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            // Long-form biography in the reader's language, if prepared.
            if let bio = isUrdu ? n.bioUrdu : n.bioEnglish, !bio.isEmpty {
                sectionTitle("Biography")
                localizedProse(bio)
            } else if isUrdu, (n.needsUrdu ?? false) {
                Text("An Urdu biography is being prepared.")
                    .font(.footnote).italic()
                    .foregroundStyle(DIColor.textMuted)
            }

            // Scholarly appraisals (jarḥ wa-taʿdīl): Arabic + translation if any.
            if let appraisals = n.appraisals, !appraisals.isEmpty {
                sectionTitle("Scholarly appraisals")
                ForEach(Array(appraisals.enumerated()), id: \.offset) { _, a in
                    DICard {
                        VStack(alignment: .leading, spacing: DISpacing.xs) {
                            if let who = a.scholar ?? a.scholarArabic {
                                Text(verbatim: who)
                                    .font(.caption.weight(.semibold))
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

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(DIFont.subheading)
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
                .font(.body)
                .foregroundStyle(DIColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func factRows(_ n: HadithNarrator) -> [(String, String)] {
        var rows: [(String, String)] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { rows.append((label, value)) }
        }
        add(String(localized: "Grade"), isUrdu ? (n.gradeUrdu ?? n.gradeArabic) : (n.gradeEnglish ?? n.gradeArabic))
        add(String(localized: "Kunya"), n.kunya ?? n.kunyaArabic)
        add(String(localized: "Generation"), n.generation)
        add(String(localized: "Died"), n.deathYear)
        add(String(localized: "Cities"), isUrdu ? (n.citiesArabic ?? n.cities) : (n.cities ?? n.citiesArabic))
        add(String(localized: "Affiliations"), n.affiliations ?? n.affiliationsArabic)
        if let count = n.hadithCount { add(String(localized: "Narrations"), "\(count)") }
        return rows
    }
}
