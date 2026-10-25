# Friday's memory backup: the part for Roxy (2026-10-25)

Matthew: "remember to split the work so you don't over use your usage". Claude built the logic and tests on branch
`claude/friday-memory`; Roxy builds the small Mac part below on top of that branch, then runs the Mac compile.

## Already done (Claude, tested on Linux)

- `FridayData.swift` → `FridayBackupPlan`: the URL (`Helm-Private`, `friday/memory.json`, branch `main`), `tokenProblem`,
  `request(method,token,body)`, `uploadBody(content,sha)`, `existing(data)` (sha + decoded content), `problem(status)`.
- `Conversation.swift`: `onChange` (called after every successful save), `mergeRestored(_ archive:) -> Int`,
  `fridayRecall(_:)`, and the bigger starting memory (newest 100 notes or about 10,000 characters).
- `Live.swift`: the `recall_notes` tool. `FeedData.swift`: its feed label.

## To build (Roxy): one new file, `FridayBackup.swift`, plus two small hookups

1. `@MainActor final class FridayBackup: ObservableObject`
   - `static let tokenService = "GameCompanion.HelmPrivateToken"` (saved with `Keychain.write` / `read` / `exists` / `remove`,
     the same way `MeetingHub.tokenService` is; never logged, never shown).
   - Published: `hasToken`, `tokenInput`, `status`, `busy`, `lastBackup` (a Date kept in UserDefaults "friday.backup.last").
   - `attach(_ store: ConversationStore)`: keep it weakly; set `store.onChange = { [weak self] in self?.schedule() }`.
   - `saveToken()`: check `FridayBackupPlan.tokenProblem`; on success write it, clear the box, `hasToken = true`.
     `forgetToken()`: remove it.
   - `schedule()`: cancel the waiting task; wait 120 seconds; then `backupNow()`. So a burst of new notes makes one upload.
   - `backupNow()`: only if `hasToken` and `store.memoryEnabled` and the file at `store.fileURL` exists. GET (to learn the sha;
     a 404 means first upload, no sha), then PUT `uploadBody(fileData, sha:)`. 200 or 201: set `lastBackup`, status "Backed up
     to Helm-Private". Otherwise `status = FridayBackupPlan.problem(status:)`. No network error text with headers or bodies.
   - `restore()`: GET; `existing(data)`; decode `MemoryArchive`; `store.mergeRestored(archive)`; status "Restored N notes"
     or "Nothing new in the backup".
2. `CompanionInterface.swift`: `@StateObject var backup = FridayBackup()`, and `backup.attach(conversation)` in `.onAppear`.
3. The Memory page (`memoryPage`), under the notes list, a small card titled "Backup to Helm-Private (your private repo)":
   SecureField for the key, Save, a "Make a key" link (`FridayBackupPlan.keyPage`), Back up now, Restore, the status line and
   "Last backup: …". One line of help: "A fine-grained key limited to Helm-Private only, with Contents set to Read and write."
4. Register `FridayBackup` in `rebuild.sh` SOURCES and in `make_gpt_bundle.py`.

Rules: the key is the only credential and it touches Helm-Private only; never Helm-Private's contents in the public thread; nothing paid.
Compile the exact branch hash on the Mac (57+1 sources) and post exit code and hash in the room. Claude reviews and merges.
