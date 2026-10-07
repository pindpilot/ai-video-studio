# AI Video Studio

Native iPhone project: Swift 6, SwiftUI, iOS 17+. Work proceeds in milestones.

## Current state: M0 source scaffold, NOT a working studio

Five tabs and modular package boundaries exist. Provider adapters, project persistence,
queue, generation, timeline and export are not implemented. Matrix entries describe
verified documentation, not tested credentials or live availability. No API keys are bundled.
No analytics. Paid calls and account farming are prohibited.

**No compiler runs locally. Milestones M0-M2 have successful macOS CI package tests and unsigned device builds. No simulator or physical-device visual/audio check has happened. An unsigned CI IPA is not a signed install or a finished app.**

## Open on a Mac

Open `AIStudio.xcodeproj` in Xcode 16 or newer, choose AIStudio, then build on an iOS 17+
simulator. Run `swift test` in `Packages/StudioKit` for package tests. These commands must
succeed before a milestone is described as compiling.

## Unsigned IPA without a developer team

The manual GitHub Actions workflow uses a macOS runner, runs package tests, builds with
`CODE_SIGNING_ALLOWED=NO`, and packages the resulting device app under `Payload`.
Download the `AIStudio-unsigned` artifact only from a successful run. It is unsigned,
not App Store-ready, not installed, and not proof that sideload signing will work.
The user must sign it with their own on-device signing setup. Never put certificates,
passwords, provisioning profiles or API keys in a public repository.

## If a paid Apple Developer account is added later

In Xcode Signing & Capabilities, select the actual team and an available bundle ID.
For a registered device, use Product > Archive, then Organizer > Distribute App and
choose the appropriate Development/Ad Hoc method. For TestFlight, upload a signed
archive to App Store Connect using the account's team. Distribution requires valid
profiles, entitlements and device registration where applicable; this scaffold includes
no signing identity or provisioning profile.

## Modules

- StudioCore: schema-versioned models, pipeline stages.
- ProviderKit: registry, fallback actor and Cloudflare script/image adapters.
- StudioPersistence: SwiftData project store and idempotent persistent DAG jobs.
- StudioMedia: project sidecars, installed-voice audio files and editable SRT. Timeline/export comes later.
- StudioFeatures: SwiftUI tabs, saved projects, reviewed generation workspace and Model Manager.

See PROVIDER_MATRIX.md, ASSUMPTIONS.md, and docs/ADDING_A_PROVIDER.md.

## M1 provider infrastructure

Capability protocols, manifest constraints, normalized file-backed results, a sync failover actor,
shared quota buckets, Retry-After parsing, bounded transient retries and offline mock tests are
implemented. Model Manager groups documented candidates, saves toggles/order, configures keys
in Keychain and runs the exact three-model mock demo. Real adapters and connection/usage tests
are deliberately pending. No real candidate is labelled Available. Async provider jobs require
the next milestone's persistent queue; this engine will not silently resubmit them.


## M3 reviewed workspace

1. Create a named project with an idea, then open it in Projects. You can write and edit the script without a provider account.
2. Optional cloud generation: in Settings enter your Cloudflare account ID and confirm it is Workers Free, not Workers Paid. Check that plan in the official dashboard yourself. In Models configure the Cloudflare token for each model you intend to use and enable that model. Keys stay in device Keychain. Cloudflare's 10,000-neuron/day allocation is shared; no metered upgrade is allowed. No remaining-quota API is assumed.
3. Script/image generation sends the labelled prompt to Cloudflare when you press its button. Outputs need review. FLUX uses documented default dimensions; no selectable generator ratio is promised. Other provider candidates have no executable adapter yet. No live cloud call is made in CI.
4. Choose an exact installed voice locale and voice to save local CAF voiceover audio. Listen and review it. If Punjabi is unavailable on that device, the app does not substitute English or another language. Device audio testing is still pending.
5. Estimate subtitles using the script and audio duration, then edit the SRT timings. This is a manual timing aid, not transcription or word alignment. Validate/save/share the SRT. Styled burned-in captions arrive with video editing.
6. Current scripts, media prompts, selected voices, subtitle text and media provenance live in atomic version-1 sidecars under Application Support/AIStudio/Projects/<project UUID>. Media files stay on disk. Generated script versions also append to the DB. Relaunch opens projects, but pending async-provider jobs are not yet actively polled.

M3 does not implement queue-driven Auto-create, streamed generation, imported-media transcription, ElevenLabs, Mistral, video composition or export. Cloudflare contract tests are synthetic sanitized docs-based fixtures, not recordings of live success. Availability is not inferred from key presence or a green compile. Device/simulator visual validation and sideload signing remain unverified.
