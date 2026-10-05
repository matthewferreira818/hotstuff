import SwiftUI
import Cocoa

// The Meeting Room page: the shared board (see MeetingData.swift) plus a box that turns Matthew's message into a
// ready-to-paste note for Claude or GPT. The chats can't see each other, so this is how they stay on the same page.
@MainActor final class MeetingHub: ObservableObject {
 @Published var board: Board?
 @Published var loading = false
 @Published var failed = false
 // Who the message is for: 0 Claude, 1 GPT, 2 a note for Claude to file on the board.
 @Published var to = 0
 @Published var draft = ""
 @Published var copied = ""
 var lastRefresh = Date.distantPast

 func refresh(force: Bool = false) async {
  guard !loading else { return }
  if !force && Date().timeIntervalSince(lastRefresh) < 240 { return }
  loading = true
  defer { loading = false }
  if let fresh = await MeetingData.fetch() { board = fresh; failed = false } else { failed = (board == nil) }
  lastRefresh = Date()
 }

 // The text that gets copied. GPT gets the whole board because it can't read the repo by itself.
 func message() -> String {
  let note = draft.trimmingCharacters(in:.whitespacesAndNewlines)
  switch to {
  case 0:
   return "Message for Claude, from Matthew (sent through the Meeting Room in my app):\n\n\(note)\n\nBefore you start, read meeting-room/BOARD.md in the hotstuff repo, and update it before you stop."
  case 1:
   let current = board?.raw ?? "(The board couldn't be loaded. Ask Matthew to paste it.)"
   return "Message for GPT, from Matthew (sent through the Meeting Room in my app):\n\n\(note)\n\nReply in plain words. If you did or decided something, finish with a \"Board update\" block in the board's format (## heading, then - [GPT] lines), so I can hand it to Claude. Never put keys, customer details or anything private in it. The current board:\n\n\(current)"
  default:
   return "Claude, please add this to meeting-room/BOARD.md under the right heading (keep it short, one owner per item, no private details), then commit and push it:\n\n\(note)"
  }
 }

 func copy() {
  let pasteboard = NSPasteboard.general
  pasteboard.clearContents()
  pasteboard.setString(message(),forType:.string)
  copied = to == 0 ? "Copied for Claude" : (to == 1 ? "Copied for GPT" : "Copied for the board")
  Task {
   try? await Task.sleep(nanoseconds:2_500_000_000)
   copied = ""
  }
 }
}

extension CompanionInterfaceView {
 var hubMeeting: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:18) {
    HStack(spacing:10) {
     hubPill("THE SHARED BOARD · FROM GITHUB",tint:HubColor.indigo)
     if let board = meeting.board, !board.updated.isEmpty {
      Text("Updated \(board.updated)").font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
     }
     Spacer()
     Button { if let url = URL(string:MeetingData.page) { NSWorkspace.shared.open(url) } } label: { Label("Open on GitHub",systemImage:"arrow.up.right.square") }
      .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
     Button { Task { await meeting.refresh(force:true) } } label: { Label(meeting.loading ? "Refreshing…" : "Refresh",systemImage:"arrow.clockwise") }
      .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
      .disabled(meeting.loading)
    }
    hubCrew
    if let board = meeting.board {
     ForEach(board.sections) { section in hubBoardSection(section) }
    } else if meeting.failed {
     hubOffline("the board")
    } else {
     ProgressView().controlSize(.large).frame(maxWidth:.infinity).padding(40)
    }
    hubComposer
    Text("Your chats can't see each other, so this board is the shared page. The repo is public: never put keys, customer details or anything private on it. The app only reads the board; Claude edits it.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
 }

 var hubCrew: some View {
  HStack(alignment:.top,spacing:14) {
   hubCrewCard("Claude","Builds the app, runs the automations and keeps the repo. Reads the board at the start of a job.","hammer.fill",HubColor.amber,"Open Claude","https://claude.ai/code")
   hubCrewCard("GPT","A second opinion and notes, in your ChatGPT Project. It can read the app but can't push to GitHub.","brain.head.profile",HubColor.green,"Open ChatGPT","https://chatgpt.com/")
   hubCrewCard("Friday","Lives in this app: she hears you and sees your game. She doesn't write to the board yet.","waveform",Noir.crimson,"Talk to Friday",nil)
  }
 }

 func hubCrewCard(_ name: String,_ job: String,_ icon: String,_ tint: Color,_ button: String,_ url: String?) -> some View {
  VStack(alignment:.leading,spacing:10) {
   ZStack {
    RoundedRectangle(cornerRadius:14,style:.continuous).fill(LinearGradient(colors:[tint,tint.opacity(0.55)],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:40,height:40)
    Image(systemName:icon).font(.system(size:17,weight:.semibold)).foregroundStyle(Color.white)
   }
   Text(name).font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
   Text(job).font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.6)).lineLimit(4).multilineTextAlignment(.leading)
   Spacer(minLength:4)
   Button {
    if let url = url, let target = URL(string:url) { NSWorkspace.shared.open(target) } else { hubSelect(.friday) }
   } label: { Label(button,systemImage:url == nil ? "waveform" : "arrow.up.right") }
    .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
  }
  .padding(16)
  .frame(maxWidth:.infinity,minHeight:170,alignment:.topLeading)
  .hubCard()
 }

 func hubOwnerTint(_ owner: String) -> Color {
  let name = owner.lowercased()
  if name.hasPrefix("claude") { return HubColor.amber }
  if name.hasPrefix("gpt") { return HubColor.green }
  if name.hasPrefix("matthew") { return HubColor.sky }
  if name.hasPrefix("friday") { return Noir.crimsonLight }
  return HubColor.slate
 }

 func hubStatusTint(_ status: String) -> Color {
  if status.hasPrefix("done") { return HubColor.green }
  if status.hasPrefix("blocked") { return Noir.crimsonLight }
  if status.hasPrefix("building") { return HubColor.amber }
  return HubColor.slate
 }

 func hubBoardSection(_ section: BoardSection) -> some View {
  VStack(alignment:.leading,spacing:12) {
   HStack(spacing:8) {
    Text(section.title).font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
    Text(String(section.items.count)).font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
   }
   if section.items.isEmpty {
    Text("Nothing here.").font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
   }
   ForEach(section.items) { item in
    HStack(alignment:.top,spacing:10) {
     if !item.owner.isEmpty { hubPill(item.owner.uppercased(),tint:hubOwnerTint(item.owner)) }
     Text(item.text).font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(item.isDone ? 0.5 : 0.85)).lineLimit(5).multilineTextAlignment(.leading)
     Spacer(minLength:8)
     if !item.status.isEmpty { hubPill(item.status.uppercased(),tint:hubStatusTint(item.status)) }
    }
   }
  }
  .padding(18)
  .frame(maxWidth:.infinity,alignment:.leading)
  .hubCard()
 }

 var hubComposer: some View {
  VStack(alignment:.leading,spacing:12) {
   Text("Send a message").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
   Picker("To",selection:$meeting.to) { Text("To Claude").tag(0); Text("To GPT").tag(1); Text("Note for the board").tag(2) }
    .pickerStyle(.segmented).labelsHidden().frame(maxWidth:440)
   TextEditor(text:$meeting.draft)
    .font(.system(size:13.5,design:.rounded))
    .scrollContentBackground(.hidden)
    .frame(minHeight:90,maxHeight:140)
    .padding(10)
    .background(RoundedRectangle(cornerRadius:14,style:.continuous).fill(Color.white.opacity(0.06)))
    .overlay(RoundedRectangle(cornerRadius:14,style:.continuous).stroke(Color.white.opacity(0.10),lineWidth:1))
   HStack(spacing:10) {
    Button { meeting.copy() } label: { Label(meeting.copied.isEmpty ? "Copy message" : meeting.copied,systemImage:meeting.copied.isEmpty ? "doc.on.doc" : "checkmark") }
     .buttonStyle(PillButtonStyle())
     .disabled(meeting.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
    Button { if let url = URL(string:"https://claude.ai/code") { NSWorkspace.shared.open(url) } } label: { Label("Open Claude",systemImage:"arrow.up.right") }
     .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    Button { if let url = URL(string:"https://chatgpt.com/") { NSWorkspace.shared.open(url) } } label: { Label("Open ChatGPT",systemImage:"arrow.up.right") }
     .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   }
   Text(meeting.to == 0 ? "Copies your message plus a line telling Claude to read the board. Paste it into any Claude chat." : (meeting.to == 1 ? "Copies your message and today's board, so GPT starts from the same page. Paste it into your GPT Project." : "Copies a note for Claude to file on the board. To carry a GPT \"Board update\" over, paste GPT's block as your message and paste this into a Claude chat."))
    .font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.45))
  }
  .padding(18)
  .frame(maxWidth:.infinity,alignment:.leading)
  .hubCard()
 }
}
