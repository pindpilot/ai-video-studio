import SwiftUI
import ProviderKit

@MainActor @Observable
final class ModelManagerStore {
    var models = ProviderCatalog.candidates
    var enabled: [String: Bool] = [:]
    var configured: [String: Bool] = [:]
    var notice = ""
    var demoAttempts: [Attempt] = []
    var runningDemo = false
    init() {
        if let data = UserDefaults.standard.data(forKey: "model-order"), let order = try? JSONDecoder().decode([String].self, from: data) {
            models.sort { (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max) }
        }
        enabled = UserDefaults.standard.dictionary(forKey: "model-enabled") as? [String: Bool] ?? [:]
        refreshKeys()
    }
    func refreshKeys() {
        for model in models { configured[model.id] = !model.needsKey || ((try? KeychainStore.read(model.id)) ?? nil) != nil }
    }
    func persist() {
        UserDefaults.standard.set(enabled, forKey: "model-enabled")
        if let data = try? JSONEncoder().encode(models.map(\.id)) { UserDefaults.standard.set(data, forKey: "model-order") }
    }
    func availability(_ model: ModelManifest) -> String {
        if model.needsKey && configured[model.id] != true { return "Needs key" }
        return "Untested - adapter pending"
    }
    func move(_ offsets: IndexSet, to target: Int, capability: Capability) {
        var group = models.filter { $0.capability == capability }; group.move(fromOffsets: offsets, toOffset: target)
        var next = group.makeIterator()
        models = models.map { $0.capability == capability ? next.next()! : $0 }; persist()
    }
    func demo() async {
        runningDemo = true; defer { runningDemo = false }
        let engine = FallbackEngine(sleep: { _ in })
        for (id, kind) in [("Mock 1", ProviderErrorClass.quotaExceeded), ("Mock 2", .modelUnavailable)] {
            let manifest = ModelManifest(id: id, provider: "Offline mock", model: id, capability: .text,
                source: .init(documentationURL: URL(string: "https://example.com")!, verifiedOn: "fixture", eligibility: .verifiedOperation),
                needsKey: false, terms: "Fixture only", dataDisclosure: "No network")
            await engine.register(manifest) { _ in throw ProviderFailure(kind, message: kind == .quotaExceeded ? "Quota exhausted" : "Model unavailable") }
        }
        let third = ModelManifest(id: "Mock 3", provider: "Offline mock", model: "Mock 3", capability: .text,
            source: .init(documentationURL: URL(string: "https://example.com")!, verifiedOn: "fixture", eligibility: .verifiedOperation),
            needsKey: false, terms: "Fixture only", dataDisclosure: "No network")
        await engine.register(third) { _ in .init(text: "Success") }
        do {
            let receipt = try await engine.execute(.init(capability: .text, text: "Demo"), chain: ["Mock 1", "Mock 2", "Mock 3"],
                configurations: ["Mock 1": .init(enabled: true), "Mock 2": .init(enabled: true), "Mock 3": .init(enabled: true)])
            demoAttempts = receipt.attempts; notice = "Offline demo succeeded. Real providers are still untested."
        } catch { notice = "Offline demo failed." }
    }
}
public struct ModelManagerView: View {
    @State private var store = ModelManagerStore()
    @State private var keyModel: ModelManifest?
    public init() {}
    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Personal use · Free only").font(.headline)
                    Text("Documentation verified is not live availability. No provider calls in M1; connection tests arrive with each adapter. Enabling a candidate does not make it runnable.").font(.footnote)
                }
                ForEach(Capability.allCases, id: \.self) { capability in
                    let group = store.models.filter { $0.capability == capability }
                    if !group.isEmpty {
                        Section(capability.rawValue.capitalized) {
                            ForEach(group) { model in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(model.provider + " · " + model.model).font(.headline)
                                    Text(store.availability(model)).foregroundStyle(.secondary)
                                    Toggle("Enable candidate", isOn: Binding(get: { store.enabled[model.id] ?? false }, set: { store.enabled[model.id] = $0; store.persist() }))
                                    Text(position(model, in: group)).font(.caption)
                                    Text(model.terms).font(.footnote)
                                    Text(model.dataDisclosure).font(.footnote).foregroundStyle(.secondary)
                                    Link("Official operation docs (verified " + model.source.verifiedOn + ")", destination: model.source.documentationURL)
                                    if model.needsKey { Button("Configure key") { keyModel = model } }
                                    if let page = model.keyPage { Link("Provider key page", destination: page) }
                                    Button("Test connection - adapter pending") {}.disabled(true)
                                }.padding(.vertical, 4)
                            }.onMove { offsets, target in store.move(offsets, to: target, capability: capability) }
                        }
                    }
                }
                Section("Offline failover demo") {
                    Text("Mock 1 quota → Mock 2 unavailable → Mock 3 success. This does not test real providers or consume credits.").font(.footnote)
                    Button("Run offline demo") { Task { await store.demo() } }.disabled(store.runningDemo)
                    ForEach(Array(store.demoAttempts.enumerated()), id: \.offset) { _, attempt in
                        Text(attempt.modelID + ": " + attempt.reason).font(.footnote)
                    }
                    if !store.notice.isEmpty { Text(store.notice).font(.footnote) }
                }
            }.navigationTitle("Model Manager").toolbar { EditButton() }
            .sheet(item: $keyModel) { model in KeyEditor(model: model) { store.refreshKeys() } }
        }
    }
    private func position(_ model: ModelManifest, in group: [ModelManifest]) -> String {
        let active = group.filter { store.enabled[$0.id] == true && store.configured[$0.id] == true && $0.source.eligibility == .verifiedOperation }
        if let index = active.firstIndex(where: { $0.id == model.id }) { return "Candidate priority #\(index + 1) of \(active.count). Adapter pending." }
        return "Not in enabled, configured candidate chain."
    }
}
private struct KeyEditor: View {
    let model: ModelManifest
    let changed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var errorMessage = ""
    var body: some View {
        NavigationStack {
            Form {
                Section(model.provider) {
                    SecureField("API key", text: $key).textContentType(.password)
                    Text("Stored only in this device's Keychain. Never bundled, synced, or logged. Key presence is not a successful connection test.").font(.footnote)
                }
                Button("Save key") {
                    do { try KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), for: model.id); key = ""; changed(); dismiss() }
                    catch { errorMessage = "Keychain could not save the key. Try again while the device is unlocked." }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove saved key", role: .destructive) {
                    do { try KeychainStore.delete(model.id); changed(); dismiss() }
                    catch { errorMessage = "Keychain could not remove the key." }
                }
                if !errorMessage.isEmpty { Text(errorMessage) }
            }.navigationTitle("API configuration")
                .toolbar { Button("Cancel") { key = ""; dismiss() } }
        }
    }
}
