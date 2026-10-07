# Decisions and open assumptions

Date: 2026-10-07. Scope is the native Swift 6 / SwiftUI brief, not the earlier PWA plan.

- Working name AI Video Studio; editable later. Bundle ID app.pindpilot.aivideostudio is provisional.
- Minimum iOS 17. Newer Apple Translation / Foundation Models / background export APIs must be availability-gated, never treated as universal.
- No Apple Developer membership confirmed. Produce an unsigned device app/IPA only after a successful Mac build. Sideload signing is performed by the user; no TestFlight promise.
- User authorized a public repository. No personal media, keys, captured conversations or account identifiers beyond public project branding belong in source.
- Paid providers stay disabled, preserving the original free-only rule. The requested optional paid toggle is deferred until the user changes that rule; enabling a toggle alone is not permission for a charge.
- Gemini and Groq have professional/developer versus consumer-use restrictions. Personal-use scope excludes both. Do not call them unrestricted. No live Gemini/Groq calls in M0.
- ElevenLabs free output: noncommercial only with published title attribution. Commercial mode cannot route to this free adapter.
- Only exact documented operations may gain an adapter. Unverified settings are not inferred from export settings. A provider returning one ratio may require visibly flagged local reframing.
- Apple Speech is only on-device when supportsOnDeviceRecognition is true and requiresOnDeviceRecognition is set. Language availability, authorization, model assets and device memory matter. No claim that all iOS 17 phones have an offline LLM.
- Local TTS voices vary by installed language. A default-language voice is not a valid substitute for requested Punjabi.
- AI video API capacity is not promised free. Imported clips and native editing/export remain distinct from text-to-video generation.
- No bundled music until an actual redistributable license is verified. User-imported tracks require provenance; a sample sine wave is not a licensed music library.
- Unknown errors classify transient, with at most two retries. Policy/invalid-input errors never reroute. Async jobs must persist identifiers before polling and avoid duplicate submission.
- This environment has no Swift or Xcode. Source is UNCOMPILED until a macOS CI run succeeds. No visual iPhone/simulator verification yet. No IPA exists.

## M1
- Infrastructure milestone, not a live-generation milestone. Catalog entries are documented candidates; adapters, health tests and official quota queries arrive with capability implementation. No keys/signups required in M1.
- Paid models are rejected even if toggled: this project remains free/no-card. Async jobs are rejected by the sync fallback engine until the persistent queue can save and resume job IDs.
- Quota reset dates are never invented. Unknown quota reset blocks the shared quota bucket until explicit recheck. Rate limits without Retry-After use a conservative 60-second cooldown, not an assertion about provider reset.
- Key presence is configuration, not authentication. All real candidates stay Untested/Needs key. Offline mock success never changes their availability.
- M0 bootstrap source-commit condition was wrong: it was re-evaluated after extraction. M1 marks bootstrap with a step output so the restored tree is committed once, with [skip ci].

## M2
- Persistence uses SwiftData (a brief-listed option). A single-writer actor owns the store; UI never touches ModelContext directly. In-memory containers are for tests; the app uses the default on-disk container.
- Schema version is a lightweight recorded marker (v2). A formal VersionedSchema migration plan lands when v3 actually changes fields; inventing migration steps now would be theatre.
- Queue execution drains sequentially: an honest concurrency cap of one until real async adapters exist. Parallelism and thermal-aware throttling arrive with real workloads, not as untested scaffolding.
- A job left "running" at relaunch is requeued because stage operations must be idempotent. A job waiting on a provider keeps its provider job ID and is only ever re-polled, never resubmitted.
- invalidRequest and policyRefused end in needsAttention for the user; they are never retried or rerouted. Other failures are retryable up to 3 times, per scene, without touching succeeded siblings.
- Background execution is still unclaimed: BGContinuedProcessingTask and background URLSession are considered at the export/download milestone, with iOS limits stated in the UI.

## M3
- First executable paths: manual scripts, Cloudflare Llama script and FLUX image adapters, installed Apple local voice to CAF, editable SRT with explicitly estimated timing. ElevenLabs, Mistral, STT, streaming, timed captions and translation remain pending, not silently mocked.
- A cloud prompt sends data only after the user presses its labelled generation button. Tokens are model-specific Keychain entries, Cloudflare account ID is nonsecret in Settings. Confirm Workers Free before any request; metered accounts are ineligible. App does not claim to inspect the billing plan through an undocumented endpoint.
- Projects tab now opens the on-disk SwiftData store and calls relaunch reconciliation. Provider-waiting jobs remain waiting with an honest notice, not a fake successful re-poll. M3 interactive steps save atomic output sidecars; queue-driven Auto-create wiring remains pending.
- Version-1 sidecar documents hold current script, prompts, language/voice and media provenance. Script generation also appends a DB script version. Media remains in the project's Application Support directory. Existing unreadable sidecars are never overwritten by a fresh blank document.
- Subtitle timing estimates require listening and review; no audio transcription is claimed. SRT text can be replaced with manually authored timing. No default-language substitution for Punjabi voiceover.
- A compiled artifact is not a device audio or UI test. Live calls require the user's real free account/key and approved project prompt; no signups, card entry, hidden quota use or fake credentials are needed for CI.

## M4
- Video means imported clips and locally rendered still-image slideshow, not cloud AI text-to-video. Default fit preserves all content with black bars, no silent crop. Reframe pan/zoom UI and crossfades remain pending.
- Timeline supports sequential trim ranges, midpoint split, reorder/delete, speed 0.25-4x, clip/voiceover volume and 30-entry undo/redo in this screen session. Edits autosave version-1 timeline sidecar; undo history is session-only.
- Limits: 100 clips, 10-minute total, at most 10-minute source duration per clip. Full source files are copied locally; no proxy editor/stream download claim yet.
- Export is local MP4, 30fps, selectable 9:16/16:9/1:1 720p/1080p. H.264 verified in real fixture test, not inferred only from a filename. Photos saving, burned captions, transitions and ducking remain pending.
- Background/lock cancels export. Partial files are deleted. App asks the user to remain in foreground and review the whole finished video/audio before sharing. No automatic sharing or publishing.

## M4.1 device-usability hotfix
- User reported inability to add photos on his iPhone. Code inspection found the app only used fileImporter (Files), not Photos. This is a verified missing path, not a reproduced physical-device crash.
- Native PhotosPicker uses the out-of-process system picker and does not request broad photo-library permission. No NSPhotoLibraryUsageDescription is needed for this selected-item-only path. Reference: https://developer.apple.com/documentation/photokit/selecting-photos-and-videos-in-ios
- Copy picked temporary files before their transfer lifetime ends; normalize HEIC/JPEG/PNG with EXIF transform to bounded JPEGs on the TimelineFiles actor. Failed/iCloud selections give a retry notice. No cloud upload is involved.
- Chat-shaped home is a simple local slideshow assistant, not an unconfigured chatbot or a hidden AI call. Add photos, duration, shape, export, preview and share are visible on one screen. Prompts are explicitly reference-only; advanced M3 cloud tools remain in More options.
- Existing projects are retained. New home reopens its last project ID and uses the same timeline storage/export engine. Physical-device photo selection still requires the owner's ESign-installed test.
- M5 music/enhancement/background-removal/scene-detection/gallery are paused until this hotfix ships.
