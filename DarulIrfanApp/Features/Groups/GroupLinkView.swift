import SwiftUI

/// A Halqah opened from a notification ("New post in your Halqah", "Halqah
/// zikr has started"): the member's own groups are loaded and the one named is
/// shown, with its post or its live session. A phone not signed in, or a
/// member no longer in that Halqah, sees the Halqah page instead, which says
/// what to do.
@MainActor
struct GroupLinkView: View {
    let groupID: String
    let dependencies: AppDependencies?

    @State private var model = GroupsModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .diScreenBackground()
            case .ready:
                if let group = model.groups.first(where: { $0.id == groupID }) {
                    GroupDetailView(group: group, service: model.service, dependencies: dependencies)
                } else {
                    GroupsHomeView(dependencies: dependencies)
                }
            case .signedOut, .failed:
                GroupsHomeView(dependencies: dependencies)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            model.platform = dependencies?.officialPlatform
            await model.start()
        }
    }
}
