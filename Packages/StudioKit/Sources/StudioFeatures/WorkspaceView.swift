import SwiftUI
import ProviderKit
import StudioPersistence
import StudioMedia
import StudioCore
@preconcurrency import AVFoundation

@MainActor @Observable
final class WorkspaceStore {
    let project: ProjectSnapshot
    let database: StudioStore
    var document = WorkspaceDocument()
    var files: WorkspaceFiles?
    var busy = false
    var notice = ""
    var attempts: [Attempt] = []
    var imageURL: URL?
    var audioURL: URL?
    var subtitleURL: URL?
    var duration = 30.0
    var loaded = false
    var engine = FallbackEngine()
    var voice = LocalVoiceWriter()
    var player: AVAudioPlayer?
    var work: Task<Void, Never>?
    init(project: ProjectSnapshot, database: StudioStore) { self.project = project; self.database = database }
    func load() async {
        guard !loaded else { return }
        do {
            let files = try WorkspaceFiles(projectID: project.id); self.files = files
            document = try await files.load()
            if let image = document.image { imageURL = try await files.url(for: image.relativePath) }
            if let audio = document.voiceover { audioURL = try await files.url(for: audio.relativePath) }
            loaded = true
        } catch { notice = "Project files could not be opened. They were not overwritten." }
    }
    func save() async {
        guard loaded, let files else { return }
        do { try await files.save(document) }
        catch { notice = "Changes could not be saved. Keep this screen open and try again." }
    }
    func cloud(_ capability: Capability) async throws -> ExecutionReceipt {
        guard UserDefaults.standard.bool(forKey: "cloudflare-free-confirmed") else {
            throw ProviderFailure(.invalidRequest, message: "Confirm Workers Free in Settings before a cloud request")
        }
        guard let files else { throw ProviderFailure(.invalidRequest, message: "Project is not open") }
        let id = capability == .text ? "cf-text" : "cf-image"
        guard (UserDefaults.standard.dictionary(forKey: "model-enabled") as? [String: Bool])?[id] == true else {
            throw ProviderFailure(.invalidRequest, message: "Enable the Cloudflare model in Models first")
        }
        let token = try KeychainStore.read(id) ?? ""
        let account = UserDefaults.standard.string(forKey: "cloudflare-account") ?? ""
        let adapter = CloudflareAdapter(accountID: account, token: token, outputDirectory: files.directory)
        guard let manifest = ProviderCatalog.candidates.first(where: { $0.id == id }) else {
            throw ProviderFailure(.modelUnavailable, message: "Model is not registered")
        }
        await engine.register(manifest) { request in
            if request.capability == .text { return try await adapter.generateText(request) }
            return try await adapter.generateImage(request)
        }
        let text = capability == .text ? "Write a short voiceover script in \(document.language) about this idea: \(project.idea)" : document.imagePrompt
        return try await engine.execute(.init(capability: capability, text: text), chain: [id], configurations: [id: .init(enabled: true, configured: !token.isEmpty)])
    }
    func start(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy, loaded else { return }
        busy = true; notice = ""; attempts = []
        work = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.work = nil }
            do { try await operation(); await self.save() }
            catch is CancellationError { self.notice = "Cancelled" }
            catch let failure as ChainFailure {
                self.attempts = failure.attempts; self.notice = "No provider succeeded. Check Models and the attempt reasons. No paid fallback was used."
            }
            catch let failure as ProviderFailure { self.notice = failure.message }
            catch VoiceWriteFailure.unavailableLanguage { self.notice = "No installed voice matches this language. Choose a supported voice; no other language is substituted." }
            catch { self.notice = "This step failed. Existing output was kept. Check the input and try again." }
        }
    }
    func generateScript() {
        start {
            let receipt = try await self.cloud(.text); try Task.checkCancellation()
            self.attempts = receipt.attempts; self.document.script = receipt.result.text ?? ""
            await self.database.saveScriptVersion(self.document.script, projectID: self.project.id)
            self.notice = "Script ready for review. Check facts before using it."
        }
    }
    func generateImage() {
        start {
            let receipt = try await self.cloud(.image); try Task.checkCancellation()
            guard let file = receipt.result.file else { throw ProviderFailure(.transient, message: "No image file returned") }
            self.attempts = receipt.attempts; self.imageURL = file
            self.document.image = .init(provider: "Cloudflare", model: "FLUX.1 schnell", prompt: self.document.imagePrompt, relativePath: file.lastPathComponent, licenseNote: "Provider model terms apply. No selectable output ratio promised.")
            self.notice = "Image saved. Review before use."
        }
    }
    func synthesize() {
        start {
            guard let files = self.files else { return }
            let url = try await files.url(for: UUID().uuidString + ".caf")
            let seconds = try await self.voice.write(text: self.document.script, language: self.document.language, voiceID: self.document.voiceID, to: url)
            try Task.checkCancellation()
            self.duration = seconds; self.audioURL = url
            self.document.voiceover = .init(provider: "Apple on-device", model: self.document.voiceID, prompt: self.document.script, relativePath: url.lastPathComponent, licenseNote: "Local installed voice. No cloud request.")
            self.notice = "Voiceover audio saved. Play and review it."
        }
    }
    func estimateSubtitles() {
        do {
            document.subtitleSource = try SubtitleTrack.srt(SubtitleTrack.estimate(script: document.script, duration: duration))
            document.subtitlesAreEstimated = true
            notice = "Estimated timings only. Edit after listening; this is not speech recognition."
            Task { await save() }
        } catch { notice = "Enter a script and a positive duration." }
    }
    func saveSubtitles() {
        start {
            guard let files = self.files else { return }
            self.subtitleURL = try await files.writeSubtitles(self.document.subtitleSource)
            self.notice = "SRT saved. Check timing against the voiceover."
        }
    }
    func play() {
        guard let audioURL else { return }
        do { player = try AVAudioPlayer(contentsOf: audioURL); player?.play() }
        catch { notice = "Audio could not be played." }
    }
    func cancel() { work?.cancel(); voice.cancel() }
}
struct WorkspaceView: View {
    @State private var store: WorkspaceStore
    init(project: ProjectSnapshot, database: StudioStore) { _store = State(initialValue: WorkspaceStore(project: project, database: database)) }
    var body: some View {
        Form {
            Section("Script - review before continuing") {
                TextEditor(text: $store.document.script).frame(minHeight: 150).accessibilityLabel("Editable script")
                Button("Generate script with Cloudflare") { store.generateScript() }.disabled(store.busy || !store.loaded)
                Text("Idea and language go to Cloudflare. Review facts. Manual scripts work without a key.").font(.footnote)
            }
            Section("Visual") {
                TextField("Image prompt", text: $store.document.imagePrompt, axis: .vertical)
                Button("Generate image with FLUX") { store.generateImage() }.disabled(store.busy || !store.loaded)
                Text("Prompt goes to Cloudflare. Output uses provider defaults; reframing is a later editing step.").font(.footnote)
                if let url = store.imageURL { ShareLink("Share saved image", item: url) }
            }
            Section("On-device voiceover") {
                TextField("Voice locale (for example en-US)", text: $store.document.language)
                    .disabled(store.busy)
                Picker("Installed voice", selection: $store.document.voiceID) {
                    Text("Choose a voice").tag("")
                    ForEach(LocalVoiceWriter.availableVoices().filter { $0.language == store.document.language }, id: \.id) { voice in
                        Text(voice.name + " (" + voice.language + ")").tag(voice.id)
                    }
                }
                Button("Save voiceover audio") { store.synthesize() }.disabled(store.busy || store.document.voiceID.isEmpty || !store.loaded)
                Text("Text stays on this device. Punjabi is only offered if a matching installed voice exists.").font(.footnote)
                if let url = store.audioURL {
                    Button("Play voiceover") { store.play() }
                    ShareLink("Share audio", item: url)
                }
            }
            Section("Subtitles - editable SRT") {
                TextField("Audio duration in seconds", value: $store.duration, format: .number)
                Button("Estimate from script and duration") { store.estimateSubtitles() }.disabled(store.busy || !store.loaded)
                if store.document.subtitlesAreEstimated { Text("Estimated, not transcribed. Review every timing.").font(.footnote) }
                TextEditor(text: $store.document.subtitleSource).frame(minHeight: 180).accessibilityLabel("Editable SRT subtitles")
                Button("Validate and save SRT") { store.saveSubtitles() }.disabled(store.busy || !store.loaded)
                if let url = store.subtitleURL { ShareLink("Share SRT", item: url) }
            }
            Section {
                if store.busy { ProgressView(); Button("Cancel") { store.cancel() } }
                if !store.notice.isEmpty { Text(store.notice) }
                ForEach(Array(store.attempts.enumerated()), id: \.offset) { _, attempt in Text(attempt.modelID + ": " + attempt.reason).font(.footnote) }
                Text("Video composition, STT alignment and caption styling come later. No paid fallback.").font(.footnote)
            }
        }
        .navigationTitle(store.project.name)
        .task { await store.load() }
        .onChange(of: store.document.script) { _, _ in Task { await store.save() } }
        .onChange(of: store.document.imagePrompt) { _, _ in Task { await store.save() } }
        .onChange(of: store.document.voiceID) { _, _ in Task { await store.save() } }
        .onChange(of: store.document.language) { _, _ in store.document.voiceID = ""; Task { await store.save() } }
        .onChange(of: store.document.subtitleSource) { _, _ in Task { await store.save() } }
        .onDisappear { store.cancel(); Task { await store.save() } }
    }
}
