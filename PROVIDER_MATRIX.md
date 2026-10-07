# Provider matrix

Verified date: 2026-10-07. Intended use: personal, noncommercial. Free-only, no payment card.

**Documentation-verified does not mean configured, tested, or live-available.** M0 contains no
adapters. Any field marked unknown must be resolved from official operation docs before
adapter code. No guessed endpoints. Output export ratios do not imply generator support.

## Documented operation candidates

| Function / provider | Official operation docs | Endpoint / auth | Mode | Ratios / duration / resolution | Free and rate terms per docs, 2026-10-07 | M0 status |
| --- | --- | --- | --- | --- | --- | --- |
| Text / Cloudflare Llama 3.2 3B | https://developers.cloudflare.com/workers-ai/models/llama-3.2-3b-instruct/ | POST https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/run/@cf/meta/llama-3.2-3b-instruct ; bearer account API token | synchronous or streamed | text; 80k context documented, no media export settings | Shared 10,000 neurons/account/day, free plan, model/task rate limits | Documentation verified, untested. Primary candidate |
| Image / Cloudflare FLUX.1 schnell | https://developers.cloudflare.com/workers-ai/models/flux-1-schnell/ | POST https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/run/@cf/black-forest-labs/flux-1-schnell ; bearer token | synchronous | prompt max 2048 chars, steps default 4 max 8. Exact selectable ratio/resolution not shown in fetched operation schema; do not invent them | Same 10k/day shared bucket; image task default 720 RPM, not a free-image count | Documentation verified; constraint schema needs confirmation before configurable ratios |
| STT / Cloudflare Whisper v3 turbo | https://developers.cloudflare.com/workers-ai/models/whisper-large-v3-turbo/ | Workers AI binding run('@cf/openai/whisper-large-v3-turbo', input); REST route requires independent exact-route confirmation before adapter | synchronous, batch option separately documented | source audio; language and task transcribe/translate. Word timestamp schema must be confirmed; do not assume | 46.63 neurons/audio minute in current pricing table, sharing account 10k/day; ASR default 720 RPM | Exact operation verified; REST/timed-output adapter not ready |
| TTS / Cloudflare MeloTTS | https://developers.cloudflare.com/workers-ai/models/melotts/ | AI model operation @cf/myshell-ai/melotts. REST exact route not present in fetched model page | synchronous | language parameter default en. Upstream supports EN/ES/FR/ZH/JA/KO, not Punjabi/Hindi; maximum duration unspecified | 18.63 neurons/audio minute, sharing 10k/day | Documentation verified; language-limited backup, untested |
| Text / Mistral | https://docs.mistral.ai/getting-started/quickstarts/studio/activate-and-generate-api-key | POST https://api.mistral.ai/v1/chat/completions ; Authorization Bearer key | synchronous, streaming needs separate operation check | text; model-specific context unknown until selected model docs | Free mode explicitly no-card; monthly included usage and per-model organization limits in console, no public guaranteed count | Primary independent candidate; model/terms/privacy check pending |
| TTS / ElevenLabs | https://elevenlabs.io/docs/api-reference/text-to-speech/convert | POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id} ; xi-api-key | synchronous audio response | voice/model-dependent languages/formats. Query GET /v1/models for TTS capability; no universal duration claimed | 10k credits/month no-card, shared products, no free rollover. Noncommercial only; published output title must credit elevenlabs.io or 11.ai | Personal-use primary candidate, untested. Choose supported language/voice, no unauthorized cloning |
| STT / Deepgram | https://developers.deepgram.com/reference/speech-to-text-api/listen | Operation docs fetched; exact route/auth/timing schema not extracted yet | prerecorded/streaming have distinct APIs | depends on exact model/language | https://deepgram.com/pricing states $200 signup credit, no card, no expiration; finite trial balance, not monthly renewal | Verified no-card trial newly found. Exclude adapter until exact operation record complete |
| STT / AssemblyAI | https://support.assemblyai.com/articles/5370767329-can-i-sign-up-for-free | Async /v2/transcript and wss://streaming.assemblyai.com/v3/ws mentioned; auth details not yet verified | async / streaming | exact timing/model limits unknown | finite $50 audio trial; no need to add card until upgrading | Trial candidate only, excluded from adapter set until full operation docs |
| Background removal / remove.bg | https://www.remove.bg/api | POST https://api.remove.bg/v1.0/removebg ; X-Api-Key per official examples | synchronous | free preview output; high-resolution rights/cost not assumed | first 50 API calls/month documented; exact no-card signup and preview resolution not verified | Exclude until no-card/output constraints confirmed |

Cloudflare shared pricing/limits: https://developers.cloudflare.com/workers-ai/platform/pricing/ and
https://developers.cloudflare.com/workers-ai/platform/limits/ . A model requiring a paid
billing method is ineligible even when the account has a free allocation. Multiple keys
and model variants do not reset shared quotas. Deprecated unsuffixed Llama 3.1 8B and
Gemma 3 12B must not be used from remembered examples.

ElevenLabs free allowance: https://elevenlabs.io/pricing and https://join.elevenlabs.io/developer-api .
Publishing license: https://help.elevenlabs.io/hc/en-us/articles/13313564601361-Can-I-publish-the-content-I-generate-on-the-platform .
Melo language/license source: https://github.com/myshell-ai/MeloTTS/blob/main/README.md .
Mistral console quotas: https://docs.mistral.ai/admin/billing-usage/usage-limits . Privacy docs
conflict; inspect actual opt-out before use: https://docs.mistral.ai/admin/monitor-comply/privacy-data-controls
and https://help.mistral.ai/en/articles/347617-do-you-use-my-user-data-to-train-your-artificial-intelligence-models .

## On-device candidates, no provider quota

| Function | Official docs | Operation / auth / mode | Constraints and limits | Status |
| --- | --- | --- | --- | --- |
| Speech audio / AVSpeechSynthesizer | https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer | write(_:toBufferCallback:) audio buffers, local, no key | installed voice/language availability, device resources. A playback-only method is not an exported audio track | exact operation documented, implementation/test pending |
| STT / Apple Speech | https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition | SFSpeechRecognizer supportsOnDeviceRecognition; permission required; asynchronous | enforce requiresOnDeviceRecognition, check language availability; no guaranteed Punjabi offline support | candidate; full recognition/timestamp docs must be read before adapter |
| Background mask / Vision | https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest | VNGenerateForegroundInstanceMaskRequest, local | availability/image handling must be compiled and device-tested; no cloud quota | documented candidate |
| Translation / Apple | https://developer.apple.com/documentation/translation | Translation framework; full exact session operation pending | iOS 18+ availability-gated per project scope; language assets and supported pairs required | not a universal iOS17 fallback; adapter excluded until exact docs |
| Script / Apple Foundation Models | https://developer.apple.com/documentation/foundationmodels | on-device system model, framework availability check | Apple Intelligence compatible device required; not all iOS17 phones. Exact SDK/locale/context checks pending | excluded from enabled base until capability and OS checks implemented |
| STT / WhisperKit | not fetched in M0 | no endpoint assumed | model download, license, device RAM/thermal and exact dependency revision require verification | unverified, not included yet |
| Enhancement / Core Image, Core ML | not yet exact-operation verified | no assumed neural upscale model | basic filters differ from AI upscale; a Core ML framework is not a bundled licensed model | unverified, not included yet |
| Shot detection / AVFoundation frame difference | design only, exact operations not yet sourced | local frame analysis, separate from LLM scene planning | thresholds/resources need tests; not claimed implemented | pending |

## Not included (documented exclusions or incomplete verification)

| Candidate / function | Official evidence or current status | Reason |
| --- | --- | --- |
| Gemini / text, TTS, translation | https://ai.google.dev/gemini-api/terms (effective March 23, 2026) | User confirmed personal use. Terms describe professional/business developer purposes, not consumer use; age 18+ and no sensitive/personal inputs for unpaid services. Exclude, not unrestricted |
| Gemini / image, Imagen, video Veo/Omni | https://ai.google.dev/gemini-api/docs/pricing ; https://ai.google.dev/gemini-api/docs/pricing.md.txt | These generation API free rows say Not available; consumer website credits do not grant app API usage |
| Groq / text, STT, TTS | https://console.groq.com/docs/legal/services-agreement | Not for consumer use; no personal-app adapter |
| Cerebras / text | https://inference-docs.cerebras.ai/support/rate-limits | Verified payment method required, $5/30-day trial, no renewing free tier |
| Claude / text | https://docs.anthropic.com/en/api/messages | Operation documented; no no-card renewable free API grant verified. Not included |
| OpenAI / text, images, voice, Whisper API | https://developers.openai.com/api/docs/pricing | Paid API pricing. ChatGPT consumer free access is not API credit. Exact operation adapters not scoped in free-only app |
| Stability / images, enhancement, background | https://platform.stability.ai/pricing | Paid credit pricing, no recurring no-card allowance verified. Endpoints not guessed |
| Black Forest Labs direct / images | https://docs.bfl.ml/quick_start/pricing | Paid operation pricing; Cloudflare-hosted FLUX is a separate documented route |
| Hugging Face routed / text, image, video, audio | https://huggingface.co/docs/inference-providers/main/en/pricing | Only $0.10/month, subject to change. Exact model/provider operation constraints incomplete. Experimental, not dependable free video |
| Pollinations / all | https://github.com/pollinations/pollinations/blob/HEAD/APIDOCS.md ; https://pollinations.ai/ | Current key/Pollen model contradicts legacy anonymous/free FAQ. No current fixed free capacity validated; exclude |
| Runway / video | https://docs.dev.runwayml.com/guides/pricing/ | API paid credits; no recurring no-card allowance verified |
| Luma / video | https://lumalabs.ai/api | API discovery page only; exact generation/pricing docs not verified, excluded |
| Kling / video | https://kling.ai/document-api/pricing/base/video.md | Paid unit pricing, consumer free credits not transferable API capacity |
| MiniMax / video | https://platform.minimax.io/docs/guides/video-generation | API operation candidate documented, free-tier and exact billing not verified, excluded |
| fal / video/open models | https://fal.ai/docs/documentation/model-apis/pricing | Pay-for-output/compute, no renewing free capacity verified; model-specific endpoints not guessed |
| Replicate / video/open models | https://replicate.com/docs/topics/billing | Paid compute/output and limited trial where offered; no guaranteed free recurring video |
| DeepL / translation | https://support.deepl.com/hc/en-us/articles/360021200939-DeepL-API-Free | Official help says API Free can no longer be purchased. Legacy 500k/month does not establish new signup availability |
| Google Cloud / translation, TTS | exact operation and no-card signup not verified | Separate from Gemini; not included |
| Azure / TTS, STT, translation | https://azure.microsoft.com/en-us/pricing/details/speech/ and https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-speech-to-text discovered but not fetched | Free product allowance is not proof of no-card account eligibility. Unverified/excluded |
| Photoroom / background | https://docs.photoroom.com/remove-background-api-basic-plan/quickstart-guide | Official operation discovered; exact free signup/resolution/API grant not verified, excluded |
| AI music / Eleven Music or other | https://elevenlabs.io/pricing | Product listed but exact official music API operation/license quota not verified, excluded. Use user-imported tracks only until license verified |

## Intended personal-use chain, not yet connected

- Text: Cloudflare free-compatible model and Mistral free, order adjustable after quality/latency tests.
- Image: Cloudflare FLUX. No reliable independent recurring free backup proved yet.
- Voice: ElevenLabs personal/noncommercial -> supported local AVSpeechSynthesizer voice -> MeloTTS where language fits.
- STT: eligible local Apple Speech -> Cloudflare Whisper; optional finite Deepgram/AssemblyAI trials only after full operation verification.
- Text-to-video: not enabled. Imported clips and local editing are distinct features.
- No moderation bypass. No automatic paid upgrade. No cross-provider hidden video checkpoint.

All state starts Untested/Needs key, not Available. Unknown quota stays unknown; estimate
local usage only with that label. Future exact-operation rows must include supported output
constraints and sanitized contract fixtures before adapter code is committed.

## M3 exact-operation record (2026-10-07)

- Cloudflare text route re-fetched: https://developers.cloudflare.com/workers-ai/models/llama-3.2-3b-instruct/ . POST route exactly as above, bearer token, messages, stream=false, max_tokens, result.response. No streaming claim.
- Cloudflare image route re-fetched: https://developers.cloudflare.com/workers-ai/models/flux-1-schnell/ . POST route exactly as above, bearer token, prompt 1-2048 characters, steps=4 (maximum 8), result.image is base64 JPEG. No width/height/ratio requested because this model's operation page does not document them. Local reframing is a separate future edit operation.
- Envelope and REST auth: https://developers.cloudflare.com/api/resources/ai/methods/run/ and https://developers.cloudflare.com/workers-ai/get-started/rest-api/ . Account ID and token required; token uses Workers AI Read/Edit. The general guide's old Llama 3.1 example is NOT this adapter's selected model.
- Free-only gate: https://developers.cloudflare.com/workers-ai/platform/pricing/ . 10,000 neurons/day shared, Workers Free stops at the allocation; Workers Paid can charge. App blocks cloud requests until the user confirms the account uses Workers Free. This declaration is not an API-verified billing-plan check. No paid gateway or automatic upgrade.
- Local exported audio: https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/write(_:tobuffercallback:) plus https://developer.apple.com/documentation/avfaudio/avaudiofile/init(forwriting:settings:) and https://developer.apple.com/documentation/avfaudio/avaudiofile/write(from:) . Synthesized PCM buffers written to a CAF audio file. Installed voice locales only, no quota or cloud authentication. Completion/cancel: https://developer.apple.com/documentation/avfaudio/avspeechsynthesizerdelegate/speechsynthesizer(_:didfinish:) and https://developer.apple.com/documentation/avfaudio/avspeechsynthesizerdelegate/speechsynthesizer(_:didcancel:) . Voices: https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice/speechvoices() . Device audio validation still required.
- Subtitle estimate is a manual timing aid, not an STT provider. Script words are evenly distributed across a user-entered or synthesized duration. Editable SRT is validated before saving. No claim of word-level alignment, transcription, translation or on-video styling.
- Tests use synthetic sanitized contract-shape fixtures based on docs. They are NOT recordings of successful live provider calls. No production keys or live calls in CI. Cloudflare availability remains untested until a user's actual project step succeeds; no recurring free independent image backup is claimed.

## M4 local video operations (2026-10-07)

No cloud text-to-video adapter added. Local imported clips and image slideshows are separate from AI-generated video.

- AVAssetWriter H.264 pixel-buffer video: https://developer.apple.com/documentation/avfoundation/avassetwriter and https://developer.apple.com/documentation/avfoundation/avassetwriterinputpixelbufferadaptor plus https://developer.apple.com/documentation/avfoundation/avassetwriterinputpixelbufferadaptor/append(_:withpresentationtime:) . Local, no key/quota. Still frames written at 30fps.
- AVMutableComposition clip/audio insertion: https://developer.apple.com/documentation/avfoundation/avmutablecomposition and https://developer.apple.com/documentation/avfoundation/avmutablecompositiontrack/inserttimerange(_:of:at:) . Sequential trims, speed-scaled time ranges, volume mix. No transition or ducking claim.
- Fit-to-frame transform/video composition: https://developer.apple.com/documentation/avfoundation/avmutablevideocomposition and https://developer.apple.com/documentation/avfoundation/avmutablevideocompositionlayerinstruction/settransform(_:at:) . Black-bar fit avoids hidden crop. Export size 720/1080 short-edge with 9:16, 16:9 or 1:1 and 30fps.
- Local MP4 export: https://developer.apple.com/documentation/avfoundation/avassetexportsession/exportasynchronously(completionhandler:) and https://developer.apple.com/documentation/avfoundation/avassetexportsession/cancelexport() . Uses iOS17-compatible completion API, cancels on task cancellation or app becoming inactive, deletes partial files. Foreground-only; no unlimited background claim.
- Synthetic real media test renders a local fixture and checks duration, dimensions and H.264 subtype. This is a local export test, not a provider fixture/live-video call.
