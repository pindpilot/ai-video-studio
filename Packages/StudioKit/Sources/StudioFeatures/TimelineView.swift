import SwiftUI
import AVKit
import UniformTypeIdentifiers
import StudioMedia
import StudioPersistence
#if os(iOS)
import PhotosUI
import CoreTransferable
#endif

@MainActor @Observable
final class TimelineStore {
    var document = TimelineDocument()
    var files: TimelineFiles?
    var history: [TimelineDocument] = []
    var future: [TimelineDocument] = []
    var loaded = false
    var busy = false
    var notice = ""
    var exportURL: URL?
    var player: AVPlayer?
    var work: Task<Void, Never>?
    let exporter = VideoExporter()
    let projectID: UUID
    init(projectID: UUID) { self.projectID = projectID }
    func open() async {
        guard !loaded else { return }
        do {
            let workspace = try WorkspaceFiles(projectID: projectID)
            let files = TimelineFiles(directory: workspace.directory); self.files = files
            document = try await files.load(); loaded = true
            if let name = document.lastExportPath, TimelineDocument.safePath(name) {
                exportURL = files.directory.appendingPathComponent(name)
                player = AVPlayer(url: exportURL!)
            }
        } catch { notice = "Timeline could not be opened. Existing files were not overwritten." }
    }
    func save() async {
        guard loaded, let files else { return }
        do { try await files.save(document) } catch { notice = "Timeline could not be saved." }
    }
    func edit(_ change: (inout TimelineDocument) -> Void) {
        guard loaded, !busy else { return }
        history.append(document); if history.count > 30 { history.removeFirst() }; future = []
        change(&document); document.lastExportPath = nil; exportURL = nil; player = nil
        Task { await save() }
    }
    func undo() {
        guard !busy, let previous = history.popLast() else { return }
        future.append(document); document = previous; exportURL = nil; player = nil; Task { await save() }
    }
    func redo() {
        guard !busy, let next = future.popLast() else { return }
        history.append(document); document = next; exportURL = nil; player = nil; Task { await save() }
    }
    func importURL(_ url: URL, kind: MediaKind) async {
        guard loaded, !busy, let files else { return }
        busy = true; defer { busy = false }
        do {
            let name = try await files.importFile(url, kind: kind)
            var duration = 5.0
            if kind == .video {
                let asset = AVURLAsset(url: files.directory.appendingPathComponent(name))
                duration = try await asset.load(.duration).seconds
                guard duration.isFinite, duration >= 0.1 else { throw TimelineFailure.invalidClip }
                duration = min(duration, 600)
            }
            history.append(document); future = []
            document.clips.append(.init(relativePath: name, kind: kind, duration: duration))
            document.lastExportPath = nil; exportURL = nil; player = nil; await save()
            notice = "Media copied locally. Only import files you may use."
        } catch { notice = "Media could not be imported. Try a supported image or video file." }
    }
    func importPhoto(_ url: URL) async -> Bool {
        guard loaded, !busy, let files, document.clips.count < 100 else { return false }
        busy = true; defer { busy = false }
        do {
            let name = try await files.importPhoto(url)
            history.append(document); future = []
            document.clips.append(.init(relativePath: name, kind: .image))
            document.lastExportPath = nil; exportURL = nil; player = nil
            await save(); notice = "Photo added. Ready to export."
            return true
        } catch { notice = "Could not load this photo. For iCloud photos, connect to the internet and retry, or use Add from Files."; return false }
    }
    func addWorkspaceImageAndVoice() async {
        guard !busy, loaded else { return }
        do {
            let workspace = try WorkspaceFiles(projectID: projectID)
            let source = try await workspace.load()
            guard let image = source.image else { notice = "Generate an image in the project workspace first, or import one."; return }
            edit {
                $0.clips.append(.init(relativePath: image.relativePath, kind: .image))
                $0.voiceoverPath = source.voiceover?.relativePath
            }
        } catch { notice = "Project assets could not be opened." }
    }
    func split(_ id: UUID) {
        guard let clip = document.clips.first(where: { $0.id == id }) else { return }
        edit { try? $0.split(id, at: clip.duration / 2) }
    }
    func export() {
        guard loaded, !busy, let files else { return }
        let snapshot = document; busy = true; notice = "Exporting locally. Keep the app open; background completion is not promised."
        work = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.work = nil }
            do {
                let url = try await self.exporter.export(snapshot, directory: files.directory)
                self.document.lastExportPath = url.lastPathComponent; self.exportURL = url; self.player = AVPlayer(url: url)
                await self.save(); self.notice = "MP4 ready. Watch the full export and check audio before sharing. Images/clips are fitted with black bars, never silently cropped."
            } catch is CancellationError { self.notice = "Export cancelled. Partial output deleted." }
            catch TimelineFailure.mediaTooShort { self.notice = "A trim extends beyond the source clip. Shorten it and export again." }
            catch { self.notice = "Export failed. Check media and trim ranges. No completed output was marked ready." }
        }
    }
    func cancel() { work?.cancel() }
}
struct TimelineView: View {
    @State private var store: TimelineStore
    @State private var importing = false
    @State private var importKind: MediaKind = .image
    #if os(iOS)
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoBusy = false
    #endif
    @Environment(\.scenePhase) private var phase
    init(projectID: UUID) { _store = State(initialValue: TimelineStore(projectID: projectID)) }
    var body: some View {
        List {
            Section("Local timeline") {
                Text("Imported clips or still-image slideshow, not AI-generated video. Up to 100 clips / 10 minutes. Fit-to-frame adds black bars.").font(.footnote)
                #if os(iOS)
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 20, matching: .images, preferredItemEncoding: .compatible) {
                    Label("Add photos from library", systemImage: "photo.badge.plus")
                }.disabled(store.busy || photoBusy || !store.loaded)
                #endif
                Button("Add image from Files") { importKind = .image; importing = true }.disabled(store.busy || !store.loaded)
                Button("Add video file") { importKind = .video; importing = true }.disabled(store.busy || !store.loaded)
                Button("Add workspace image and voiceover") { Task { await store.addWorkspaceImageAndVoice() } }.disabled(store.busy || !store.loaded)
                HStack {
                    Button("Undo") { store.undo() }.disabled(store.history.isEmpty || store.busy)
                    Button("Redo") { store.redo() }.disabled(store.future.isEmpty || store.busy)
                }
            }
            Section("Clips - reorder in Edit mode") {
                ForEach(store.document.clips) { clip in clipRow(clip) }
                    .onMove { source, target in store.edit { $0.clips.move(fromOffsets: source, toOffset: target) } }
                    .onDelete { offsets in store.edit { $0.clips.remove(atOffsets: offsets) } }
            }
            exportSection
            if let player = store.player {
                Section("Review exported video") { VideoPlayer(player: player).frame(height: 280) }
            }
            Section {
                if store.busy { ProgressView(); Button("Cancel export") { store.cancel() } }
                Text(store.notice)
                Text("Crossfades, styled captions, pan/zoom reframing, proxies and background export remain pending. Clip audio and voiceover mix at chosen volumes; automatic ducking comes later.").font(.footnote)
            }
        }
        .navigationTitle("Timeline & Export")
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
        .task { await store.open() }
        .fileImporter(isPresented: $importing, allowedContentTypes: importKind == .image ? [.image] : [.movie]) { result in
            switch result {
            case .success(let url): Task { await store.importURL(url, kind: importKind) }
            case .failure: store.notice = "Import cancelled or unavailable."
            }
        }
        #if os(iOS)
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            photoBusy = true
            Task {
                await importSelectedPhotos(items, into: store)
                selectedPhotos = []; photoBusy = false
            }
        }
        #endif
        .onChange(of: phase) { _, value in if value != .active { store.cancel() } }
        .onDisappear { store.cancel(); Task { await store.save() } }
    }
    private var exportSection: some View {
        Section("Export settings") {
            Picker("Ratio", selection: Binding(get: { store.document.ratio }, set: { value in store.edit { $0.ratio = value } })) {
                ForEach(ExportRatio.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Toggle("1080p (off = 720p)", isOn: Binding(get: { store.document.fullHD }, set: { value in store.edit { $0.fullHD = value } }))
            Text("H.264 MP4 · 30 fps · \(store.document.duration, specifier: "%.1f") seconds").font(.footnote)
            if store.document.voiceoverPath != nil {
                Slider(value: Binding(get: { store.document.voiceoverVolume }, set: { value in store.edit { $0.voiceoverVolume = value } }), in: 0...1) { Text("Voiceover volume") }
                Button("Remove voiceover") { store.edit { $0.voiceoverPath = nil } }
            }
            Button("Export local MP4") { store.export() }.disabled(store.document.clips.isEmpty || store.busy || !store.loaded)
            if let url = store.exportURL { ShareLink("Share reviewed MP4", item: url) }
        }.disabled(store.busy)
    }
    private func clipRow(_ clip: TimelineClip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(clip.kind.rawValue.capitalized + " · " + clip.relativePath.prefix(12)).font(.headline)
            if clip.kind == .video {
                TextField("Trim start (seconds)", value: numberBinding(clip.id, \.start), format: .number)
            }
            TextField("Source duration (seconds)", value: numberBinding(clip.id, \.duration), format: .number)
            Slider(value: numberBinding(clip.id, \.speed), in: 0.25...4) { Text("Speed") }
            Text("Speed \(clip.speed, specifier: "%.2f")× · output \(clip.outputDuration, specifier: "%.1f")s").font(.caption)
            if clip.kind == .video {
                Slider(value: Binding(get: { store.document.clips.first(where: { $0.id == clip.id })?.volume ?? 1 }, set: { value in store.edit { doc in if let index = doc.clips.firstIndex(where: { $0.id == clip.id }) { doc.clips[index].volume = value } } }), in: 0...1) { Text("Clip volume") }
            }
            Button("Split at midpoint") { store.split(clip.id) }.disabled(clip.duration < 0.2)
        }.disabled(store.busy)
    }
    private func numberBinding(_ id: UUID, _ key: WritableKeyPath<TimelineClip, Double>) -> Binding<Double> {
        Binding(get: { store.document.clips.first(where: { $0.id == id })?[keyPath: key] ?? 0 }, set: { value in
            store.edit { if let index = $0.clips.firstIndex(where: { $0.id == id }) { $0.clips[index][keyPath: key] = value } }
        })
    }
}

#if os(iOS)
/// File transfer avoids loading full-resolution multi-photo selections into RAM.
struct PickedPhoto: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(received.file.pathExtension.isEmpty ? "img" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: target)
            return PickedPhoto(url: target)
        }
    }
}
@MainActor
func importSelectedPhotos(_ items: [PhotosPickerItem], into store: TimelineStore) async {
    var added = 0
    for item in items {
        do {
            guard let photo = try await item.loadTransferable(type: PickedPhoto.self) else { continue }
            defer { try? FileManager.default.removeItem(at: photo.url) }
            if await store.importPhoto(photo.url) { added += 1 }
        } catch { continue }
    }
    store.notice = "Added \(added) of \(items.count) photos. " + (added == items.count ? "Tap Export video when ready." : "Some photos failed. Download iCloud originals and retry, or use Add from Files.")
}
#endif
