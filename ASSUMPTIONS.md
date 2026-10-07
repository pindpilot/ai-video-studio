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
