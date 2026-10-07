import Foundation
public enum ProviderCatalog {
    // These are documented candidates, not executable adapters. Registration happens separately.
    public static let candidates: [ModelManifest] = [
        .init(id: "cf-text", provider: "Cloudflare", model: "Llama 3.2 3B", capability: .text,
              source: source("https://developers.cloudflare.com/workers-ai/models/llama-3.2-3b-instruct/"),
              keyPage: URL(string: "https://dash.cloudflare.com/profile/api-tokens"),
              terms: "10,000 neurons/day shared across all Workers AI models. No paid upgrade.",
              dataDisclosure: "Prompt and script sent to Cloudflare when an adapter is enabled.", quotaBucket: "cloudflare"),
        .init(id: "cf-image", provider: "Cloudflare", model: "FLUX.1 schnell", capability: .image,
              source: source("https://developers.cloudflare.com/workers-ai/models/flux-1-schnell/"),
              keyPage: URL(string: "https://dash.cloudflare.com/profile/api-tokens"),
              terms: "Shared 10,000 neurons/day. Selectable ratio/resolution still unverified.",
              dataDisclosure: "Image prompts sent to Cloudflare when an adapter is enabled.", quotaBucket: "cloudflare"),
        .init(id: "eleven-speech", provider: "ElevenLabs", model: "Voice/model selection pending", capability: .speech,
              source: source("https://elevenlabs.io/docs/api-reference/text-to-speech/convert"),
              keyPage: URL(string: "https://elevenlabs.io/app/developers/api-keys"),
              terms: "10k credits/month. Noncommercial only. Published title must credit elevenlabs.io or 11.ai. No voice cloning without consent.",
              dataDisclosure: "Voiceover text sent to ElevenLabs when an adapter is enabled.", quotaBucket: "elevenlabs"),
        .init(id: "apple-speech", provider: "Apple on-device", model: "AVSpeechSynthesizer", capability: .speech,
              source: source("https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer"), needsKey: false,
              terms: "No cloud quota. Installed voice and language availability vary. Audio export adapter pending.",
              dataDisclosure: "Voiceover text stays on the device."),
        .init(id: "mistral-text", provider: "Mistral", model: "Selection and privacy check pending", capability: .text,
              source: source("https://docs.mistral.ai/getting-started/quickstarts/studio/activate-and-generate-api-key", eligibility: .unverified),
              terms: "No-card free mode documented; model limits and privacy settings need confirmation.",
              dataDisclosure: "Do not send prompts until model and privacy settings are verified.")
    ]
    private static func source(_ url: String, eligibility: ProviderEligibility = .verifiedOperation) -> ProviderSource {
        .init(documentationURL: URL(string: url)!, verifiedOn: "2026-10-07", eligibility: eligibility)
    }
}
