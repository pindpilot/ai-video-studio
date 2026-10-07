# Adding a provider

This is the implementation contract for the next milestone, not a working plug-in loader yet.

1. Verify the exact operation in official API documentation and add its source/date,
   endpoint/auth, request limits, language/ratio/duration/resolution and usage/license
   conditions to PROVIDER_MATRIX.md. Unverified = not eligible.
2. Add one adapter file conforming to the relevant normalized capability protocol.
3. Add one manifest entry. Do not change UI or queue code for a new model.
4. Add recorded, sanitized contract fixtures. Never include keys or personal media.
5. Classify quota/rate/unavailable/auth/transient/input/policy errors. Follow Retry-After.
6. Require configuration in Keychain, explicit enablement and capability eligibility.
   No hidden paid fallback. If the quota is shared, record the shared account bucket.
7. Prove mock fallback and all-fail tests, then test live availability only through
   the user-controlled Model Manager. Documentation verification is not a connection test.
8. Never silently change languages, voice, ratio, licensing or moderation behavior.

M1 API: add a ModelManifest, implement the capability protocol and register the adapter's normalized operation with FallbackEngine.register. Every operation closure is Sendable. GenerationResult media is a disk URL, not an in-memory blob. Mark model constraints explicitly; empty lists mean unknown/unsupported, never wildcard. ProviderFailure summaries must be adapter-authored and sanitized. Keep prompts, keys, response bodies and URL query values out of logs. 403 conservatively stops as policyRefused unless documented provider error codes safely distinguish authentication. 429 is rateLimited unless a verified body schema proves quota exhaustion. Never reroute policy/invalid-request errors. Async adapters must go through the next milestone's queue, not this sync executor.

Contract tests: ProviderKitTests uses offline mock closures and includes every error class, bounded retry, all-fail, shared quotas, cooldown, cancellation and the exact three-model example. No network calls in CI.
