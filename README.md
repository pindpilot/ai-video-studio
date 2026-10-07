# AI Video Studio

Native iPhone project: Swift 6, SwiftUI, iOS 17+. Work proceeds in milestones.

## Current state: M0 source scaffold, NOT a working studio

Five tabs and modular package boundaries exist. Provider adapters, project persistence,
queue, generation, timeline and export are not implemented. Matrix entries describe
verified documentation, not tested credentials or live availability. No API keys are bundled.
No analytics. Paid calls and account farming are prohibited.

**No compiler ran locally. No IPA has been built. No simulator screenshot has been reviewed.**

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
- ProviderKit: registry and capability interfaces (next milestone).
- StudioPersistence: persistent jobs and project stores (planned).
- StudioMedia: AVFoundation timeline and export (planned).
- StudioFeatures: accessible SwiftUI shell and later feature screens.

See PROVIDER_MATRIX.md, ASSUMPTIONS.md, and docs/ADDING_A_PROVIDER.md.
