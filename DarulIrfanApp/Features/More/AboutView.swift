import SwiftUI

/// About Darul Irfan: app identity, a short verified introduction to Silsila
/// Naqshbandia Owaisiah, source website, contact details, and
/// acknowledgements. All organizational facts come from
/// Docs/RESEARCH_NOTES.md (verified against naqshbandiaowaisiah.org).
@MainActor
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DISpacing.md) {
                identityCard
                silsilaCard
                headquartersCard
                sourceAndContactCard
                acknowledgementsLink
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Identity

    private var identityCard: some View {
        DICard {
            VStack(spacing: DISpacing.sm) {
                Text(verbatim: "دارالعرفان")
                    .font(DIFont.urduBody(scale: 1.7))
                    .foregroundStyle(DIColor.primaryDeep)
                    .environment(\.layoutDirection, .rightToLeft)

                Text("Darul Irfan")
                    .font(DIFont.heading)
                    .foregroundStyle(DIColor.textPrimary)

                Text("Light of Sacred Knowledge")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textMuted)

                Text("Version \(appVersionText)")
                    .font(.caption)
                    .foregroundStyle(DIColor.textMuted)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
        }
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Silsila

    private var silsilaCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Silsila Naqshbandia Owaisiah")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("Darul Irfan is the companion app of Silsila Naqshbandia Owaisiah, a Sufi order whose spiritual lineage traces to Khawajah Owais Qarni. The order's method is Zikr-e Khafi Qalbi with Pas Anfas — \"guarding every breath\". A distinguishing feature of the Owaisiah way is spiritual bai'at directly at the hands of the holy Prophet ﷺ.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)

                Text("The order was revived in the last century by Shaikh Allah Yar Khan (1904–1984) and afterwards led by Hazrat Ameer Muhammad Akram Awan (RA). It is presently led by Sheikh-e-Silsila Hazrat Ameer Abdul Qadeer Awan (MZA), born 26 March 1973 in Munara, District Chakwal.")
                    .font(.subheadline)
                    .foregroundStyle(DIColor.textPrimary)
            }
        }
    }

    private var headquartersCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                Text("Headquarters")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Label {
                    Text(verbatim: "Dar ul Irfan, Munara, Khushab Road, District Chakwal, Punjab, Pakistan")
                        .font(.subheadline)
                        .foregroundStyle(DIColor.textPrimary)
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(DIColor.accent)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    // MARK: - Source & contact

    private var sourceAndContactCard: some View {
        DICard {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                Text("Source & Contact")
                    .font(DIFont.subheading)
                    .foregroundStyle(DIColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                if let websiteURL = URL(string: "https://www.naqshbandiaowaisiah.org/") {
                    Link(destination: websiteURL) {
                        Label {
                            Text(verbatim: "naqshbandiaowaisiah.org")
                        } icon: {
                            Image(systemName: "globe")
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(DIColor.primary)
                    .accessibilityLabel("Visit the source website")
                }

                if let emailURL = URL(string: "mailto:Darulirfan@gmail.com") {
                    Link(destination: emailURL) {
                        Label {
                            Text(verbatim: "Darulirfan@gmail.com")
                        } icon: {
                            Image(systemName: "envelope")
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(DIColor.primary)
                    .accessibilityLabel("Send an email")
                }

                if let phoneURL = URL(string: "tel:+92543562200") {
                    Link(destination: phoneURL) {
                        Label {
                            Text(verbatim: "+92 543 562200")
                        } icon: {
                            Image(systemName: "phone")
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(DIColor.primary)
                    .accessibilityLabel("Call Dar ul Irfan")
                }
            }
        }
    }

    // MARK: - Acknowledgements

    private var acknowledgementsLink: some View {
        NavigationLink {
            AcknowledgementsView()
        } label: {
            DICard {
                HStack(spacing: DISpacing.md) {
                    Image(systemName: "text.book.closed")
                        .foregroundStyle(DIColor.accent)
                        .accessibilityHidden(true)
                    Text("Acknowledgements")
                        .font(.body.weight(.medium))
                        .foregroundStyle(DIColor.textPrimary)
                    Spacer(minLength: DISpacing.sm)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DIColor.textMuted)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
