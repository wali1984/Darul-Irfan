import SwiftUI

/// About Darul Irfan: a premium brand moment (living emerald crest, seal,
/// wordmark, anchor verse and version), followed by a short verified
/// introduction to Silsila Naqshbandia Owaisiah, contact
/// details, and acknowledgements. All organizational facts come from
/// Docs/RESEARCH_NOTES.md (verified against naqshbandiaowaisiah.org).
@MainActor
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DISpacing.md) {
                brandCrest
                    .diAppear()
                silsilaCard
                    .diAppear(delay: 0.08)
                headquartersCard
                    .diAppear(delay: 0.14)
                sourceAndContactCard
                    .diAppear(delay: 0.20)
                acknowledgementsLink
                    .diAppear(delay: 0.26)
            }
            .padding(DISpacing.md)
        }
        .diScreenBackground()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Brand crest

    private var brandCrest: some View {
        ZStack {
            DIGradient.emerald
            DIOctagram(innerRatio: 0.5)
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 300, height: 300)
                .opacity(0.06)
                .offset(x: 90, y: -80)
                .accessibilityHidden(true)

            VStack(spacing: DISpacing.sm) {
                DISealEmblem(diameter: 96, glow: true)
                    .diBreathingGlow(color: DIColor.goldGlow, maxRadius: 20)

                Text(verbatim: "دارالعرفان")
                    .font(DIFont.urduBody(scale: 1.6))
                    .foregroundStyle(.white)
                    .diGoldGlow(radius: 10, opacity: 0.4)
                    .environment(\.layoutDirection, .rightToLeft)

                Text("Darul Irfan")
                    .font(DIFont.heading)
                    .foregroundStyle(.white)

                Text("Light of Sacred Knowledge")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))

                DIJaliDivider(tint: Color.white, opacity: 0.35)
                    .frame(width: 160)
                    .padding(.vertical, DISpacing.xs)

                Text(DIBrand.anchorVerseArabic)
                    .font(DIFont.quranArabic(scale: 0.66))
                    .foregroundStyle(.white)
                    .diGoldGlow(radius: 12, opacity: 0.5)
                    .environment(\.layoutDirection, .rightToLeft)
                    .multilineTextAlignment(.center)

                Text(verbatim: DIBrand.anchorVerseEnglish)
                    .font(.footnote.italic())
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)

                Text(verbatim: DIBrand.anchorVerseReference)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DIColor.goldGlow)

                versionChip
                    .padding(.top, DISpacing.xs)
            }
            .padding(.vertical, DISpacing.lg)
            .padding(.horizontal, DISpacing.md)
            .frame(maxWidth: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: DIRadius.lg + 6, style: .continuous))
        .shadow(color: DIColor.primaryDeep.opacity(0.35), radius: 18, x: 0, y: 10)
    }

    private var versionChip: some View {
        Text("Version \(appVersionText)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, DISpacing.sm)
            .padding(.vertical, DISpacing.xs)
            .background(Capsule().fill(Color.white.opacity(0.16)))
            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Silsila

    private var silsilaCard: some View {
        DIElevatedCard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                aboutHeader("Silsila Naqshbandia Owaisiah", systemImage: "link")

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
        DIElevatedCard {
            VStack(alignment: .leading, spacing: DISpacing.sm) {
                aboutHeader("Headquarters", systemImage: "building.columns")

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
        DIElevatedCard {
            VStack(alignment: .leading, spacing: DISpacing.md) {
                aboutHeader("Contact", systemImage: "envelope")

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
            DIElevatedCard {
                HStack(spacing: DISpacing.md) {
                    ZStack {
                        Circle().fill(DIGradient.emerald)
                        Circle().strokeBorder(DIColor.accent.opacity(0.5), lineWidth: 1)
                        Image(systemName: "text.book.closed.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)

                    Text("Acknowledgements")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DIColor.textPrimary)
                    Spacer(minLength: DISpacing.sm)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DIColor.textMuted)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(DIPressableStyle())
        .simultaneousGesture(TapGesture().onEnded { DIHaptics.soft() })
    }

    // MARK: - Shared

    private func aboutHeader(_ titleKey: LocalizedStringKey, systemImage: String) -> some View {
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
