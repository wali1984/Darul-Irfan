import SwiftUI

/// Open-source, translation, and content attributions.
@MainActor
struct AcknowledgementsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DISpacing.md) {
                adhanCard
                translationCard
                contentCard
                azanRecordingsCard
                chimeCard
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var adhanCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("adhan-swift")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)

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

    private var translationCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Qur'an Translation")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("The English translation of the Qur'an included in this app is by Muhammad Marmaduke Pickthall (The Meaning of the Glorious Koran, 1930), which is in the public domain.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)
            }
        }
    }

    private var contentCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Content & Artwork")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)

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
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Azan Recordings")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)

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
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Notification Chime")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("The short prayer chime is an original recording created for this app, kept as a fallback alert sound.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)
            }
        }
    }
}
