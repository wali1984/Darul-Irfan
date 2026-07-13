import SwiftUI

/// Open-source, typography, translation, and content attributions.
@MainActor
struct AcknowledgementsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DISpacing.md) {
                adhanCard
                    .diAppear()
                fontsCard
                    .diAppear(delay: 0.06)
                translationCard
                    .diAppear(delay: 0.12)
                contentCard
                    .diAppear(delay: 0.18)
                azanRecordingsCard
                    .diAppear(delay: 0.24)
                chimeCard
                    .diAppear(delay: 0.30)
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var adhanCard: some View {
        DIElevatedCard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                ackHeader("adhan-swift", systemImage: "chevron.left.forwardslash.chevron.right")

                Text("Prayer times are calculated entirely on this device using the open-source adhan-swift library by Batoul Apps, used under the MIT License.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)

                if let url = URL(string: "https://github.com/batoulapps/adhan-swift") {
                    Link(destination: url) {
                        Label {
                            Text(verbatim: "github.com/batoulapps/adhan-swift")
                        } icon: {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(DIColor.primary)
                    .accessibilityLabel("View the adhan-swift project on GitHub")
                }
            }
        }
    }

    private var fontsCard: some View {
        DIElevatedCard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                ackHeader("Typography", systemImage: "textformat")

                Text("Qur'an Arabic text is set in Amiri Quran, and Urdu text in Noto Nastaliq Urdu. Both typefaces are bundled and used under the SIL Open Font License 1.1.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)

                if let url = URL(string: "https://fonts.google.com/specimen/Amiri+Quran") {
                    Link(destination: url) {
                        Label {
                            Text(verbatim: "Amiri Quran · SIL OFL 1.1")
                        } icon: {
                            Image(systemName: "character.book.closed")
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(DIColor.primary)
                    .accessibilityLabel("View the Amiri Quran font project")
                }

                if let url = URL(string: "https://fonts.google.com/noto/specimen/Noto+Nastaliq+Urdu") {
                    Link(destination: url) {
                        Label {
                            Text(verbatim: "Noto Nastaliq Urdu · SIL OFL 1.1")
                        } icon: {
                            Image(systemName: "character.book.closed")
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(DIColor.primary)
                    .accessibilityLabel("View the Noto Nastaliq Urdu font project")
                }
            }
        }
    }

    private var translationCard: some View {
        DIElevatedCard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                ackHeader("Qur'an Translation", systemImage: "text.quote")

                Text("The English translation of the Qur'an included in this app is by Muhammad Marmaduke Pickthall (The Meaning of the Glorious Koran, 1930), which is in the public domain.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)
            }
        }
    }

    private var contentCard: some View {
        DIElevatedCard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                ackHeader("Content & Artwork", systemImage: "photo.artframe")

                Text("Library articles, lectures, publications, tafsir, and organizational information are provided by naqshbandiaowaisiah.org, which retains all rights to its content. The app icon and visual identity are inspired by and attributed to naqshbandiaowaisiah.org.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)

                Text("Content from the website is included in the app with the owner's permission. Items without stored text link to the original page on naqshbandiaowaisiah.org.")
                    .font(.footnote)
                    .foregroundStyle(DIColor.textMuted)
            }
        }
    }

    private var azanRecordingsCard: some View {
        DIElevatedCard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                ackHeader("Azan Recordings", systemImage: "waveform")

                Text("The azan notification clip and the full azan playback use the recording “Beautiful adhan” by Adam-synagda, from Wikimedia Commons, dedicated to the public domain under CC0 1.0.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)

                if let url = URL(string: "https://commons.wikimedia.org/wiki/File:Beautiful_adhan.ogg") {
                    Link(destination: url) {
                        Label {
                            Text(verbatim: "commons.wikimedia.org · Beautiful adhan")
                        } icon: {
                            Image(systemName: "waveform")
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(DIColor.primary)
                    .accessibilityLabel("View the azan recording on Wikimedia Commons")
                }

                Text("The Fajr azan recording is by Islamic Center Malmö, from Wikimedia Commons, used under the Creative Commons Attribution 3.0 license. The audio was extracted from the original video and converted for playback in the app.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)

                if let url = URL(string: "https://commons.wikimedia.org/wiki/File:Eid_al-Fitr_Fajr_azan_at_Malm%C3%B6_Mosque_-_19_August_2012.webm") {
                    Link(destination: url) {
                        Label {
                            Text(verbatim: "commons.wikimedia.org · Fajr azan, Malmö Mosque")
                        } icon: {
                            Image(systemName: "waveform")
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(DIColor.primary)
                    .accessibilityLabel("View the Fajr azan recording on Wikimedia Commons")
                }
            }
        }
    }

    private var chimeCard: some View {
        DIElevatedCard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                ackHeader("Notification Chime", systemImage: "bell.badge")

                Text("The short prayer chime is an original recording created for this app, kept as a fallback alert sound.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)
            }
        }
    }

    // MARK: - Shared

    private func ackHeader(_ titleKey: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: DISpacing.sm) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DIColor.accent)
                .accessibilityHidden(true)
            Text(titleKey)
                .font(DIFont.subheading)
                .foregroundStyle(DIColor.textPrimary)
        }
        .accessibilityAddTraits(.isHeader)
    }
}
