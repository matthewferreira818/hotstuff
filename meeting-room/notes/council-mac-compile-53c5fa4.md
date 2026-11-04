# Council 1A: exact-candidate Mac verification, November 4, 2026

The complete 60-source app at `53c5fa419037ad7f17d1ccb065a00c9b5112352c` compiled on the Mac with exit **0**, **0 errors**. Both the complete data checks and the isolated existing Council checks passed with exit **0**. No app source edits were needed.

## Candidate and environment

- Candidate: `53c5fa419037ad7f17d1ccb065a00c9b5112352c` (master snapshot), including the integration at `9cc16f57ad8da16e98db5c569a6340920e41bff1` and the jump-in fix at `937b76e08fb4834d9187df799c70c79129a0276a`.
- macOS 27.2, arm64, Apple Swift 6.4 (`swiftlang-6.4.0.34.1`).
- The source list was extracted from this candidate's `tools/game_companion/rebuild.sh`. Only its compiler invocation was run: `xcrun swiftc -O -parse-as-library -target arm64-apple-macos27.0 <all 60 SOURCES> -o <temporary binary>`.
- All 60 source hashes were rechecked after the build. SHA-256 of the canonical sorted source-hash manifest: `740818bd5422b0ed798b02ef6d91da03cf4d5e9d2e10b9ec121528cffae61abb`.
- This review branch adds only this report and its GPT-owned board item. It does not change Swift, production settings, accounts, or workflows.

## Results

| Check | Compile exit | Run exit | Result |
|---|---:|---:|---|
| Complete app, 60 sources, optimization enabled | 0 | Not run | 0 errors; build-script warning count 30 |
| Existing complete DataChecks, 21 sources, CouncilData included, Mac import option below | 0 | 0 | All data checks passed; 0 warnings |
| Existing Council checks extracted verbatim into a standalone harness with CouncilData | 0 | 0 | All Council checks passed |

The Council checks cover turn order, previous-speaker context, duplicate-start refusal, limits, Stop, interruption, stale-output rejection, error handling, and output truncation. They exercise scripted local test replies only. The fixed `CouncilModel.send()` validates an interruption before `run()` cancels the old task; this was reviewed in source. The SwiftUI page was compiled, not interactively exercised.

## Warning counting

The build script counts every line containing `warning:`. Swift prints each warning in both its diagnostic header and source annotation: **30 matching lines correspond to 15 warning diagnostics**, compared with the previously reported baseline of 28 matching lines. The Council warning is `HubCouncil.swift:121:6`: deprecated `onChange(of:perform:)`; use the newer zero- or two-parameter form in a later UI cleanup. No warning fix was mixed into this verification.

- `tools/game_companion/Companion.swift:272:10: warning: 'installTap(onBus:bufferSize:format:block:)' was deprecated in macOS 27.0 [#DeprecatedDeclaration]`
- `tools/game_companion/Companion.swift:297:8: warning: 'installTap(onBus:bufferSize:format:block:)' was deprecated in macOS 27.0 [#DeprecatedDeclaration]`
- `tools/game_companion/Live.swift:480:48: warning: 'play()' was deprecated in macOS 27.0 [#DeprecatedDeclaration]`
- `tools/game_companion/Live.swift:747:33: warning: 'play()' was deprecated in macOS 27.0 [#DeprecatedDeclaration]`
- `tools/game_companion/Live.swift:753:10: warning: 'connect(_:to:format:)' was deprecated in macOS 27.0 [#DeprecatedDeclaration]`
- `tools/game_companion/Live.swift:760:11: warning: 'installTap(onBus:bufferSize:format:block:)' was deprecated in macOS 27.0 [#DeprecatedDeclaration]`
- `tools/game_companion/Live.swift:778:35: warning: 'play()' was deprecated in macOS 27.0 [#DeprecatedDeclaration]`
- `tools/game_companion/ClipEditor.swift:44:10: warning: 'add' was deprecated in macOS 27.0: Use the appropriate AVAssetReader.outputProvider(for:...) overload for your output and optional adaptor instead [#DeprecatedDeclaration]`
- `tools/game_companion/ClipEditor.swift:45:16: warning: 'startReading()' was deprecated in macOS 27.0: Use start() instead [#DeprecatedDeclaration]`
- `tools/game_companion/ClipEditor.swift:50:29: warning: 'copyNextSampleBuffer()' was deprecated in macOS 27.0: Use AVAssetReaderOutput.Provider.next() instead [#DeprecatedDeclaration]`
- `tools/game_companion/ClipEditor.swift:105:21: warning: 'AVMutableVideoComposition' was deprecated in macOS 26.0: Use AVVideoComposition.Configuration instead [#DeprecatedDeclaration]`
- `tools/game_companion/ClipEditor.swift:105:21: warning: 'init(asset:applyingCIFiltersWithHandler:)' was deprecated in macOS 15.0: Use videoCompositionWithAsset:applyingCIFiltersWithHandler:completionHandler: instead [#DeprecatedDeclaration]`
- `tools/game_companion/Helper.swift:160:26: warning: 'activateIgnoringOtherApps' was deprecated in macOS 14.0: ignoringOtherApps is deprecated in macOS 14 and will have no effect. [#DeprecatedDeclaration]`
- `tools/game_companion/Helper.swift:227:29: warning: 'activateIgnoringOtherApps' was deprecated in macOS 14.0: ignoringOtherApps is deprecated in macOS 14 and will have no effect. [#DeprecatedDeclaration]`
- `tools/game_companion/HubCouncil.swift:121:6: warning: 'onChange(of:perform:)' was deprecated in macOS 14.0: Use `onChange` with a two or zero parameter action closure instead. [#DeprecatedDeclaration]`

## Complete data-check command on the Mac

The first standalone combined compile failed (exit 1, 17 error diagnostics / 34 matching error lines, no test run). On this Mac, `import Foundation` alone exposes incomplete CGRect APIs in the hands geometry checks. A minimal type-check reproduced the failure; importing CoreGraphics resolved it. This is separate from the successful complete app build, whose framework imports already supply the geometry APIs.

The second combined compile used the compiler's implicit CoreGraphics import option. No checked-in source was changed. The existing documented command also omits the newly required `CouncilData.swift`; it is included here.

Run from `tools/game_companion/`:

```sh
xcrun swiftc -parse-as-library -Xfrontend -import-module -Xfrontend CoreGraphics ClipMath.swift MeetingData.swift SpeechData.swift ThreadData.swift StripeData.swift StreamData.swift FeedData.swift ChatData.swift SecretFile.swift HandsData.swift VodData.swift AutopilotData.swift VoiceOverData.swift WebData.swift ObsData.swift VideoLabData.swift HelperData.swift FridayData.swift GuardData.swift CouncilData.swift checks/DataChecks.swift -o /tmp/helm-data-checks
/tmp/helm-data-checks
```

## Scope and limits

No install, signing, app launch, engine launch, credentials, provider calls, payments, or trades. The compiled app binary was never executed. Only the offline check executables ran. The checks use a synthetic temporary test vault, not Friday's real saved secrets. This verifies compilation and logic checks, not a GUI smoke test, microphone, voice, provider streaming, or real AI integration. Council remains Phase 1A, with visibly labelled test replies.
