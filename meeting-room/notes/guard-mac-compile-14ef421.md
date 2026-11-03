# Guard Mac compile — 14ef421

Exact candidate: `14ef4210f9442a0d991bfd1021b41532228f06b7` (Claude's requested `claude/guard` candidate).

Compiler-only validation on Matthew's Mac: **exit 1**, **28 warnings**, **58 Swift sources**. Warnings match the supplied baseline of 28. macOS 27.2, arm64, Apple Swift 6.4.

The compiler reports that the SwiftUIMacros plugin is unavailable for @State in HubGuard.swift. This result alone does not establish whether the root cause is source or toolchain configuration. Stopped after this failure as requested; no fix, second build, app installation, signing or production launch.

## First 20 diagnostic lines

```text
<candidate>/tools/game_companion/HubGuard.swift:96:21: error: external macro implementation type 'SwiftUIMacros.StateMacro' could not be found for macro 'State()'; plugin for module 'SwiftUIMacros' not found
 94 | struct GuardPage: View {
 95 |  @ObservedObject var guardHub = GuardHub.shared
 96 |  @State private var forgetting: GuardKeyInfo?
    |                     `- error: external macro implementation type 'SwiftUIMacros.StateMacro' could not be found for macro 'State()'; plugin for module 'SwiftUIMacros' not found
 97 |  @State private var confirmUnlock = false
 98 |  @State private var pulse = false

SwiftUI.State:1:145: note: 'State()' declared here
1 | @attached(accessor, names: named(init), named(get), named(set)) @attached(peer, names: prefixed(`_`), prefixed(__), prefixed(`$`)) public macro State() = #externalMacro(module: "SwiftUIMacros", type: "StateMacro")
  |                                                                                                                                                 `- note: 'State()' declared here

<candidate>/tools/game_companion/HubGuard.swift:97:21: error: external macro implementation type 'SwiftUIMacros.StateMacro' could not be found for macro 'State()'; plugin for module 'SwiftUIMacros' not found
 95 |  @ObservedObject var guardHub = GuardHub.shared
 96 |  @State private var forgetting: GuardKeyInfo?
 97 |  @State private var confirmUnlock = false
    |                     `- error: external macro implementation type 'SwiftUIMacros.StateMacro' could not be found for macro 'State()'; plugin for module 'SwiftUIMacros' not found
 98 |  @State private var pulse = false
 99 | 

```

Paths were sanitized to <candidate>. No runtime data or credentials were read. The compile was performed in an isolated checkout without modifying the source.
