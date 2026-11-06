import SwiftUI
import AppKit

// Friday-and-me, the PRIVATE DM engine (Phase 2). The screen (LC-Pixels) uses this class; it never writes the files itself.
//
//   ~/Claude/friday-dm/            folder 700 (owner only), files 600
//     inbox.jsonl   one JSON object per line: {"id", "at", "text"}              written by send(_:) (Matthew's message)
//     outbox.jsonl  one JSON object per line: {"id", "replyTo", "at", "text"}   appended by the Friday chat (her reply); the screen shows it
//     status.json   {"<inbox id>": {"id", "at", "state"}}                       written by the engine: "waiting" | "woken" | "closed" | "unconfirmed" | "failed"
//
// The engine wakes the open chat named exactly "Friday" with FIXED text only ("new DM, read ~/Claude/friday-dm/inbox.jsonl"), through the same
// locked-down relay as every wake (SwitchboardWake.swift). The message itself never leaves these files: not to GitHub, the room, the Hotline,
// a receipt, a log or a wake. If Friday's chat isn't open the status is "closed" and the screen shows DMRules.closedNote.
// This works whether or not the Switchboard switch is ON: Matthew typing a DM to Friday is his own action, and the wake is fixed text.

@MainActor final class FridayDM: ObservableObject {
 static let shared = FridayDM()

 @Published private(set) var sent: [DMIn] = []                    // Matthew's messages, oldest first
 @Published private(set) var replies: [DMOut] = []                // Friday's replies, oldest first
 @Published private(set) var statuses: [String: DMStatus] = [:]   // by inbox id
 @Published private(set) var closedNote: String? = nil            // set while the newest DM found Friday's chat closed

 private var loop: Task<Void,Never>?
 private var started = false

 static let folderURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Claude/\(DMRules.folderName)",isDirectory:true)
 private var inboxURL: URL { Self.folderURL.appendingPathComponent(DMRules.inboxName) }
 private var outboxURL: URL { Self.folderURL.appendingPathComponent(DMRules.outboxName) }
 private var statusURL: URL { Self.folderURL.appendingPathComponent(DMRules.statusName) }

 private init() {}

 // Called once at app start (Switchboard.boot). Safe to call again.
 func start() {
  guard !started else { return }
  started = true
  ensureFolder()
  refresh()
  loop = Task { [weak self] in
   while !Task.isCancelled {
    try? await Task.sleep(nanoseconds:3_000_000_000)
    self?.refresh()
   }
  }
 }

 // MARK: for the screen

 // Writes Matthew's message and wakes Friday. Returns the inbox id (nil if the text is empty or the file can't be written).
 @discardableResult func send(_ text: String) -> String? {
  ensureFolder()
  guard let made = DMRules.inboxLine(text:text) else { return nil }
  guard append(made.line,to:inboxURL) else { return nil }
  refresh()
  return made.id
 }

 // The small note under a message ("Friday's chat is closed — open it to talk"), nil when fine.
 func note(forMessage id: String) -> String? { DMRules.note(for:statuses[id]) }

 // MARK: the engine

 private func ensureFolder() {
  let fm = FileManager.default
  try? fm.createDirectory(at:Self.folderURL,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  try? fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:Self.folderURL.path)   // also fixes a folder made earlier with looser rights
  for u in [inboxURL,outboxURL,statusURL] {
   if !fm.fileExists(atPath:u.path) { fm.createFile(atPath:u.path,contents:u == statusURL ? Data("{}".utf8) : Data(),attributes:[.posixPermissions:0o600]) }
   try? fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:u.path)
  }
 }

 private func append(_ line: String,to url: URL) -> Bool {
  guard let h = try? FileHandle(forWritingTo:url) else { return false }
  defer { try? h.close() }
  _ = try? h.seekToEnd()
  do { try h.write(contentsOf:Data((line + "\n").utf8)); return true } catch { return false }
 }

 private func refresh() {
  guard FileManager.default.fileExists(atPath:Self.folderURL.path) else { return }
  let inbox = DMRules.lines((try? Data(contentsOf:inboxURL)) ?? Data(),as:DMIn.self)
  let outbox = DMRules.lines((try? Data(contentsOf:outboxURL)) ?? Data(),as:DMOut.self)
  if inbox != sent { sent = inbox }
  if outbox != replies { replies = outbox }
  if let d = try? Data(contentsOf:statusURL), let s = try? DMRules.decoder.decode([String: DMStatus].self,from:d), s != statuses { statuses = s }
  // Wake Friday once for everything not yet handled ("read the inbox" covers them all). Mark them waiting first so a refresh can't double-send.
  let pending = DMRules.unhandled(inbox:inbox,status:statuses)
  guard !pending.isEmpty else { return }
  let ids = pending.map { $0.id }
  if WakeRunner.shared.submitDM(ids:ids) {
   mark(ids,"waiting")
  }   // over the hourly cap: left without a status, so the next refresh tries again
 }

 private func mark(_ ids: [String],_ state: String) {
  for id in ids { statuses[id] = DMStatus(id:id,at:Date(),state:state) }
  if let d = try? DMRules.encoder.encode(statuses) { try? d.write(to:statusURL,options:.atomic); try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:statusURL.path) }
  closedNote = (statuses.values.max { $0.at < $1.at }?.state == "closed") ? DMRules.closedNote : nil
 }

 // The wake finished (WakeRunner).
 func record(ids: [String],state: String) { mark(ids,state) }
}
