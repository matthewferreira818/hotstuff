# Meeting Room message refresh: implementation and Mac verification

November 4, 2026. Exact compiled implementation: `c11b6ca38646d1887b0f096cb6e9205a9a566e70` on `gpt/meeting-room-refresh`.

## Problem and resulting behavior

The installed page used a 60-second tick with a 55-second minimum gap when a GitHub connection was saved, or a 290-second minimum gap otherwise. Messages could therefore remain unseen for roughly one to five minutes.

The visible Meeting Room now checks incremental comments every five seconds with its existing saved GitHub connection. Without usable authentication, it uses a 90-second interval. Leaving the room cancels the foreground loop; the prior background refresh schedule remains. This is near-live polling, not a push connection or an instantaneous-delivery guarantee: sleep, offline periods, request duration and GitHub server delays can extend it.

Successful sends display the actual message returned by GitHub's HTTP 201 response immediately, then refresh. No optimistic or duplicate post is created. An in-flight older read merges comments by ID, preserving a just-posted message; forced refreshes requested during a read are queued rather than dropped.

## Scope and limits

- Only `MeetingData.swift`, `MeetingRoom.swift`, and the new isolated `checks/MeetingRefreshChecks.swift` change app/check behavior. No other app files are edited.
- The board file refreshes every five minutes while messages use incremental reads. A manual forced refresh also requests the board.
- Conditional ETags are bound to one exact request URL. Full or paginated first pages are not cached with an ETag, so later-page arrivals cannot be hidden by an unchanged first page. Reads merge and retain the most recent 300 messages; update pagination is bounded to three pages and oversized reads fail without deleting existing messages.
- GitHub's polling interval, Retry-After and exhausted-rate-limit reset headers take precedence over fast refresh. Failures back off. The header shows the last successful message check with seconds, or a refresh failure/pause; it doesn't present old data as newly checked.
- GETs bypass local cache, ask intermediaries to revalidate and don't attach cookies. Existing saved credentials stay inside the app's existing key reader. No new credential, service, API purchase or live AI connection is introduced.
- Existing posting permissions, message wording, sender tags, trusted-owner parsing, Guard/offline gates and public/private boundaries remain. No autonomous posting bridge is added.

## Verification

macOS 27.2, arm64, Apple Swift 6.4. All 60 app source hashes were checked again after the build. Canonical SHA-256 source-manifest digest: `2c2b9e33f28b2132465c1a0fe420e3d0efbcd713ce4e946b04154666b3795b86`.

| Check at `c11b6ca38646d1887b0f096cb6e9205a9a566e70` | Compile exit | Run exit |
|---|---:|---:|
| Exact rebuild.sh 60-source optimized app invocation, arm64-apple-macos27.0 | 0 | Not launched |
| Complete 21-source DataChecks, CouncilData included, implicit CoreGraphics import for Mac | 0 | 0 |
| New isolated MeetingRefreshChecks, 2 sources, intercepted HTTP only | 0 | 0 |

App build: **0 errors; 15 warning diagnostics**, represented by 30 matching warning lines under rebuild.sh's counting method, unchanged from the preceding Council verification. The app binary was not executed, installed or signed.

The new offline checks cover five-second/authenticated and 90-second/anonymous cadence, query encoding and page bounds, ID merging/edit replacement/deduplication, preserving just-posted IDs, retained-history bounds, actual POST-response parsing without sending a POST, ETag 304 handling, refusing a validator from another URL, disabling a full-page validator, multi-page updates, cache/cookie settings, Retry-After, polling/reset deadlines and invalid payloads. Every HTTP request is intercepted by a test URLProtocol; no token or real GitHub write is used.

From `tools/game_companion/`:

```sh
xcrun swiftc -parse-as-library MeetingData.swift checks/MeetingRefreshChecks.swift -o /tmp/room-refresh-checks
/tmp/room-refresh-checks
```

The complete data suite uses `-Xfrontend -import-module -Xfrontend CoreGraphics` on this Mac, as documented in `notes/council-mac-compile-53c5fa4.md` on the Council verification review branch.

Not verified: an interactive app session, real authenticated GitHub latency, live sleep/wake behavior or UI rendering. These require a reviewed update on the Mac. Claude retains review and merge; this report and its board item are documentation-only additions after the compiled implementation.
