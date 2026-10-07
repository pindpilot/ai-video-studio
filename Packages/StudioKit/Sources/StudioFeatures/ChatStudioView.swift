#if os(iOS)
import SwiftUI
import PhotosUI
import AVKit
import ImageIO
import StudioMedia
import StudioPersistence

struct ChatStudioView: View {
    let projects: ProjectListStore
    @AppStorage("chat-project-id") private var savedID = ""
    @State private var timeline: TimelineStore?
    @State private var idea = ""
    @State private var sentIdea = ""
    @State private var reply = ""
    @State private var selected: [PhotosPickerItem] = []
    @State private var importingPhotos = false
    @State private var fromFiles = false
    @State private var seconds = 5.0
    @State private var showProjects = false
    @State private var setupBusy = false
    @FocusState private var typing: Bool
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    welcome
                    if !sentIdea.isEmpty { bubble(sentIdea, user: true) }
                    if !reply.isEmpty { bubble(reply, user: false) }
                    if let timeline {
                        attachments(timeline)
                        if let player = timeline.player {
                            VideoPlayer(player: player).frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        if !timeline.notice.isEmpty { Text(timeline.notice).font(.callout).foregroundStyle(.secondary) }
                        if timeline.busy || importingPhotos { ProgressView(importingPhotos ? "Loading photos..." : "Working...") }
                        if timeline.work != nil { Button("Cancel export") { timeline.cancel() } }
                        if let url = timeline.exportURL { ShareLink(item: url) { Label("Save or share video", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent) }
                    } else {
                        ProgressView("Opening your studio...")
                        if !projects.notice.isEmpty { Text(projects.notice).foregroundStyle(.red) }
                    }
                    Text("Photos stay on this phone. This screen makes a photo slideshow, not AI-generated video. Cloud AI tools are under Advanced tools.").font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("AI Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { showProjects = true } label: { Image(systemName: "clock.arrow.circlepath") }.accessibilityLabel("Saved projects") }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New chat") { Task { await newProject() } }.disabled(importingPhotos || timeline?.busy == true)
                        NavigationLink("Models & API keys") { ModelManagerView() }
                        NavigationLink("Settings") { SettingsView() }
                        if let timeline { NavigationLink("Timeline editor") { TimelineView(projectID: timeline.projectID) } }
                        if let database = projects.database, let timeline,
                           let project = projects.projects.first(where: { $0.id == timeline.projectID }) {
                            NavigationLink("Advanced tools") { WorkspaceView(project: project, database: database) }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("More options")
                }
            }
            .sheet(isPresented: $showProjects) { projectSheet }
            .fileImporter(isPresented: $fromFiles, allowedContentTypes: [.image]) { result in
                if case .success(let url) = result, let timeline { Task { _ = await timeline.importPhoto(url) } }
            }
            .onChange(of: selected) { _, items in
                guard !items.isEmpty, let timeline else { return }
                importingPhotos = true
                Task {
                    await importSelectedPhotos(items, into: timeline)
                    selected = []; importingPhotos = false
                }
            }
            .task {
                await projects.open()
                guard timeline == nil, let database = projects.database else { return }
                if let id = UUID(uuidString: savedID), projects.projects.contains(where: { $0.id == id }) {
                    await openProject(id)
                } else {
                    let project = await database.createProject(name: "Photo video", idea: "Local photo slideshow")
                    projects.projects = await database.projects()
                    await openProject(project.id)
                }
            }
            .onChange(of: phase) { _, value in if value != .active { timeline?.cancel() } }
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.tint)
            Text("What do you want to make?").font(.title2.bold())
            Text("Add your photos below, describe your idea, then tap Export video.")
            Text("Example: a portrait reel of my favourite photos.").font(.callout).foregroundStyle(.secondary)
        }.padding(.vertical, 12)
    }
    private func bubble(_ text: String, user: Bool) -> some View {
        HStack {
            if user { Spacer(minLength: 30) }
            Text(text).padding(14).background(user ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
            if !user { Spacer(minLength: 30) }
        }
    }
    private func attachments(_ store: TimelineStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.document.clips.isEmpty {
                Text("Attached: \(store.document.clips.count) · \(store.document.duration, specifier: "%.0f") seconds").font(.headline)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(store.document.clips) { clip in
                            VStack {
                                if clip.kind == .image, let files = store.files {
                                    PhotoThumbnail(url: files.directory.appendingPathComponent(clip.relativePath))
                                } else { Image(systemName: "film").frame(width: 80, height: 80) }
                                Button("Remove") { store.edit { $0.clips.removeAll { $0.id == clip.id } } }.font(.caption)
                            }
                        }
                    }
                }
                .disabled(store.busy || importingPhotos)
                HStack {
                    Text("Seconds per photo")
                    Stepper("\(Int(seconds))", value: $seconds, in: 1...10).onChange(of: seconds) { _, value in
                        store.edit { doc in for index in doc.clips.indices where doc.clips[index].kind == .image { doc.clips[index].duration = value; doc.clips[index].speed = 1 } }
                    }
                }.disabled(store.busy || importingPhotos)
                Picker("Video shape", selection: Binding(get: { store.document.ratio }, set: { value in store.edit { $0.ratio = value } })) {
                    Text("Portrait").tag(ExportRatio.portrait); Text("Square").tag(ExportRatio.square); Text("Wide").tag(ExportRatio.landscape)
                }.pickerStyle(.segmented).disabled(store.busy)
            }
        }
    }
    private var composer: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom) {
                TextField("Describe your video...", text: $idea, axis: .vertical).lineLimit(1...4).focused($typing)
                Button { sendIdea() } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.accessibilityLabel("Send idea").disabled(idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || timeline == nil)
            }.padding(12).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
            HStack {
                PhotosPicker(selection: $selected, maxSelectionCount: 20, matching: .images, preferredItemEncoding: .compatible) {
                    Label("Add photos", systemImage: "photo.badge.plus")
                }.buttonStyle(.bordered).disabled(timeline == nil || importingPhotos || timeline?.busy == true)
                Button { typing = false; timeline?.export() } label: { Label("Export video", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent).disabled(timeline == nil || timeline?.document.clips.isEmpty == true || importingPhotos || timeline?.busy == true)
            }
            Button("Add from Files instead") { fromFiles = true }.font(.caption).disabled(timeline == nil || importingPhotos || timeline?.busy == true)
        }.padding().background(.regularMaterial)
    }
    private var projectSheet: some View {
        NavigationStack {
            List(projects.projects, id: \.id) { project in
                Button(project.name) { showProjects = false; Task { await openProject(project.id) } }.disabled(timeline?.busy == true || importingPhotos)
            }.navigationTitle("Saved projects").toolbar { Button("Done") { showProjects = false } }
        }
    }
    private func sendIdea() {
        sentIdea = idea.trimmingCharacters(in: .whitespacesAndNewlines); idea = ""; typing = false
        reply = "I'll use your attached photos in order, with \(Int(seconds)) seconds per photo. Add photos, choose the shape and tap Export video. Your idea is a reference here; it does not automatically generate images, music or captions."
    }
    private func openProject(_ id: UUID) async {
        let store = TimelineStore(projectID: id); await store.open()
        timeline = store; savedID = id.uuidString
        sentIdea = ""; reply = ""
        seconds = store.document.clips.first(where: { $0.kind == .image })?.duration ?? 5
    }
    private func newProject() async {
        guard !setupBusy, let database = projects.database else { return }
        setupBusy = true; defer { setupBusy = false }
        let project = await database.createProject(name: "Photo video \(projects.projects.count + 1)", idea: "Local photo slideshow")
        projects.projects = await database.projects(); await openProject(project.id)
    }
}
private struct PhotoThumbnail: View {
    let url: URL
    @State private var data: Data?
    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }.frame(width: 80, height: 80).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: url) {
            data = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 240, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return Optional<Data>.none }
                let bytes = NSMutableData()
                guard let output = CGImageDestinationCreateWithData(bytes, "public.jpeg" as CFString, 1, nil) else { return nil }
                CGImageDestinationAddImage(output, image, nil)
                guard CGImageDestinationFinalize(output) else { return nil }
                return bytes as Data
            }.value
        }
    }
}
#endif
