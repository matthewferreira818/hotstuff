import Foundation

@main struct ReviewChecks {
 @MainActor static func main() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CompanionReviewChecks-\(UUID().uuidString)")
  let file = directory.appendingPathComponent("memory.json")
  defer { try? FileManager.default.removeItem(at:directory) }
  let store = ConversationStore(fileURL:file,load:false)
  precondition(!store.memoryEnabled && !store.shareMemoryWithGoogle && !store.initiativeEnabled)
  store.noteDraft = "PRIVATE_MEMORY_SENTINEL"
  store.remember()
  precondition(!FileManager.default.fileExists(atPath:file.path))
  precondition(!store.instructions(cloud:true).contains("PRIVATE_MEMORY_SENTINEL"))

  store.enableMemory(true)
  precondition(FileManager.default.fileExists(atPath:file.path))
  precondition(store.instructions(cloud:false).contains("PRIVATE_MEMORY_SENTINEL"))
  precondition(!store.instructions(cloud:true).contains("PRIVATE_MEMORY_SENTINEL"))
  store.shareMemoryWithGoogle = true
  precondition(store.instructions(cloud:true).contains("PRIVATE_MEMORY_SENTINEL"))
  let permissions = try FileManager.default.attributesOfItem(atPath:file.path)[.posixPermissions] as! NSNumber
  precondition(permissions.intValue == 0o600)

  store.enableMemory(false)
  precondition(!store.shareMemoryWithGoogle)
  let reopened = ConversationStore(fileURL:file)
  precondition(!reopened.memoryEnabled && reopened.notes.count == 1)
  precondition(!reopened.instructions(cloud:false).contains("PRIVATE_MEMORY_SENTINEL"))
  reopened.removeNote(reopened.notes[0].id)
  precondition(ConversationStore(fileURL:file).notes.isEmpty)

  reopened.proposalTitle = "DECLINED_TOPIC_SENTINEL"
  reopened.proposalPurpose = "A topic to decline for this session"
  reopened.queueProposal()
  reopened.decide(reopened.proposals[0].id,accepted:false)
  precondition(reopened.instructions(cloud:false).contains("DECLINED_TOPIC_SENTINEL"))
  precondition(!reopened.instructions(cloud:true).contains("DECLINED_TOPIC_SENTINEL"))
  let start = Date()
  reopened.enableInitiative(true)
  reopened.lastInitiative = start
  precondition(!reopened.claimInitiative(now:start.addingTimeInterval(60)))
  precondition(reopened.claimInitiative(now:start.addingTimeInterval(1200)))
  precondition(!reopened.claimInitiative(now:start.addingTimeInterval(1201)))
  reopened.stopInitiative()
  precondition(!reopened.claimInitiative(now:start.addingTimeInterval(3600)))
  reopened.deleteAll()
  precondition(!FileManager.default.fileExists(atPath:file.path))
  precondition(reopened.notes.isEmpty && reopened.proposals.isEmpty)

  // Friday's own notes (remember_this / forget_this) and the Google switch surviving a restart.
  let friday = ConversationStore(fileURL:file,load:false)
  precondition(friday.fridayRemember("Loves Ella Langley",kind:"likes").contains("switched off") && friday.notes.isEmpty)
  friday.enableMemory(true)
  friday.shareMemoryWithGoogle = true
  precondition(friday.fridayRemember("Loves Ella Langley",kind:"likes") == "Saved to my memory on his Mac." && friday.fridayRemember("Loves Ella Langley",kind:"likes") == "I already had that one.")
  precondition(friday.fridayRemember("his password is hunter2",kind:"other").contains("private") && friday.notes.count == 1)
  precondition(friday.instructions(cloud:true).contains("[Likes] Loves Ella Langley"))
  let back = ConversationStore(fileURL:file)
  precondition(back.memoryEnabled && back.shareMemoryWithGoogle && back.notes.count == 1)
  precondition(back.fridayForget("ella") == "Forgot it." && back.notes.isEmpty && back.fridayForget("ella").contains("don't have"))
  back.enableMemory(false)
  precondition(!ConversationStore(fileURL:file).shareMemoryWithGoogle)
  back.deleteAll()

  precondition(CompanionPolicy.usesScreen(page:0))
  precondition(!CompanionPolicy.usesScreen(page:1) && !CompanionPolicy.usesScreen(page:2))
  precondition(CompanionPolicy.allowsAutomatic(engine:1,page:0,preview:false))
  precondition(!CompanionPolicy.allowsAutomatic(engine:0,page:0,preview:false))
  precondition(!CompanionPolicy.allowsAutomatic(engine:1,page:1,preview:false))
  precondition(!CompanionPolicy.allowsAutomatic(engine:1,page:0,preview:true))
  print("PASS: opt-in storage, cloud consent, pause/restart, removal, deletion, session declines, initiative cooldown, and local capture/automatic policy.")
 }
}
