import SwiftUI
import StudioCore
public struct StudioRootView: View {
    public init() {}
    public var body: some View {
        TabView {
            CreateView().tabItem { Label("Create", systemImage: "sparkles") }
            MilestoneView(title: "Projects", message: "Saved projects arrive with the persistence milestone.", icon: "folder")
                .tabItem { Label("Projects", systemImage: "folder") }
            MilestoneView(title: "Gallery", message: "No media yet. Assets will retain provider and license provenance.", icon: "photo.on.rectangle")
                .tabItem { Label("Gallery", systemImage: "photo.on.rectangle") }
            ModelManagerView()
                .tabItem { Label("Models", systemImage: "square.stack.3d.up") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
private struct CreateView: View {
    @State private var idea = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Your idea") {
                    TextField("Describe the video you want to make", text: $idea, axis: .vertical)
                        .lineLimit(4...8).accessibilityLabel("Video idea")
                }
                Section("Reviewable pipeline") {
                    ForEach(PipelineStage.allCases, id: \.self) { stage in
                        Label(stage.title, systemImage: "circle")
                    }
                }
                Section {
                    Text(StudioBuildStatus.milestone).font(.footnote).foregroundStyle(.secondary)
                    Text("Auto-create and manual editing are not implemented in this scaffold.").font(.footnote)
                }
            }.navigationTitle("AI Video Studio")
        }
    }
}
private struct MilestoneView: View {
    let title: String
    let message: String
    let icon: String
    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: icon, description: Text(message))
                .navigationTitle(title)
        }
    }
}
private struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("Privacy") {
                    Label("No analytics", systemImage: "hand.raised")
                    Text("No API keys are bundled. Provider keys are stored in this device's Keychain.")
                }
                Section("Spending") {
                    Text("Paid providers are disabled. No account farming or quota bypass.")
                }
                Section("Build status") { Text(StudioBuildStatus.milestone) }
            }.navigationTitle("Settings")
        }
    }
}
