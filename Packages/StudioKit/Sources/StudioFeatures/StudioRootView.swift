import SwiftUI
import StudioCore
import StudioPersistence

@MainActor @Observable
final class ProjectListStore {
    var database: StudioStore?
    var projects: [ProjectSnapshot] = []
    var notice = ""
    var ready = false
    func open() async {
        guard !ready else { return }
        do {
            let store = StudioStore(modelContainer: try StudioStore.makeContainer())
            database = store
            let waiting = await store.resumeAfterLaunch()
            projects = await store.projects(); ready = true
            if !waiting.isEmpty { notice = "Saved provider jobs are waiting. Polling adapters are not connected yet; they will not be submitted again." }
        } catch { notice = "The project database could not be opened. Existing files were not deleted." }
    }
    func create(name: String, idea: String) async {
        guard let database else { return }
        _ = await database.createProject(name: name, idea: idea)
        projects = await database.projects()
    }
}
public struct StudioRootView: View {
    @State private var store = ProjectListStore()
    public init() {}
    public var body: some View {
        TabView {
            CreateView(store: store).tabItem { Label("Create", systemImage: "sparkles") }
            ProjectsView(store: store).tabItem { Label("Projects", systemImage: "folder") }
            NavigationStack {
                ContentUnavailableView("Gallery", systemImage: "photo.on.rectangle", description: Text("Saved assets are available inside each project. Filtered gallery arrives later."))
            }.tabItem { Label("Gallery", systemImage: "photo.on.rectangle") }
            ModelManagerView().tabItem { Label("Models", systemImage: "square.stack.3d.up") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }.task { await store.open() }
    }
}
private struct CreateView: View {
    let store: ProjectListStore
    @State private var idea = ""
    @State private var name = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("New project") {
                    TextField("Project name", text: $name)
                    TextField("Describe the video", text: $idea, axis: .vertical).lineLimit(4...8)
                    Button("Save project") { Task { await store.create(name: name, idea: idea); name = ""; idea = "" } }
                        .disabled(!store.ready || name.trimmingCharacters(in: .whitespaces).isEmpty || idea.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("Open your saved project in Projects to write a script, generate an image, save voiceover and edit subtitles.").font(.footnote)
                }
                Section("Reviewable pipeline") {
                    ForEach(PipelineStage.allCases, id: \.self) { stage in Label(stage.title, systemImage: "circle") }
                }
                Section { Text(StudioBuildStatus.milestone).font(.footnote); Text(store.notice) }
            }.navigationTitle("AI Video Studio")
        }
    }
}
private struct ProjectsView: View {
    let store: ProjectListStore
    var body: some View {
        NavigationStack {
            List {
                if !store.notice.isEmpty { Text(store.notice) }
                if let database = store.database {
                    ForEach(store.projects, id: \.id) { project in
                        NavigationLink { WorkspaceView(project: project, database: database) } label: {
                            VStack(alignment: .leading) { Text(project.name); Text(project.idea).font(.caption).lineLimit(2) }
                        }
                    }
                }
                if store.projects.isEmpty { Text("No saved projects. Create one in the Create tab.") }
            }.navigationTitle("Projects")
        }
    }
}
private struct SettingsView: View {
    @AppStorage("cloudflare-account") private var account = ""
    @AppStorage("cloudflare-free-confirmed") private var freeConfirmed = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Cloudflare free-only gate") {
                    TextField("Cloudflare account ID (32 hex characters)", text: $account)
                    Toggle("I verified this account uses Workers Free, not Workers Paid", isOn: $freeConfirmed)
                    Text("Cloud requests are blocked until confirmed. Workers Paid can charge above its free allocation; this app must use Workers Free. Configure each model token in Models.").font(.footnote)
                    Link("Check official free-plan limits", destination: URL(string: "https://developers.cloudflare.com/workers-ai/platform/pricing/")!)
                }
                Section("Privacy") {
                    Text("No analytics. API keys stay in this device's Keychain. Project files stay in Application Support.")
                    Text("Cloudflare receives only the prompts for cloud steps you choose. Local voiceover and manual subtitles do not upload text or audio.")
                }
                Section("Build status") { Text(StudioBuildStatus.milestone) }
            }.navigationTitle("Settings")
        }
    }
}
