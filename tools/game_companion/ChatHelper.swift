import SwiftUI
import AppKit

// The chat helper: posts Matthew's saved links and reminders (his store, "use your Prime sub", "hit Follow") in his Twitch chat while
// he is live. Rules are in ChatData.swift. It is OFF every time the app opens and starts only when he presses Start (or asks
// Friday out loud); it posts only while Twitch says he is live; it only ever posts his own saved messages. Friday can post a saved
// message by name when he asks, never free text. The messages come from whichever Twitch account is signed in.
@MainActor final class ChatHub: ObservableObject {
 static let timersKey = "chat.timers"

 @Published var timers: [ChatTimer] = ChatHub.loadTimers() {
  didSet { UserDefaults.standard.set(try? JSONEncoder().encode(timers),forKey:ChatHub.timersKey) }
 }
 @Published var on = false
 @Published var status = ""
 @Published var posting = false
 private var lastPosted: [String:Date] = [:]
 private var lastAny: Date?
 private var postLog: [Date] = []
 private var startedAt = Date()
 private var failures = 0
 private var loop: Task<Void,Never>?
 private var twitch: TwitchClips?
 private var stream: StreamHub?
 private var feed: FridayFeed?

 static func loadTimers() -> [ChatTimer] {
  guard let data = UserDefaults.standard.data(forKey:timersKey), let list = try? JSONDecoder().decode([ChatTimer].self,from:data), !list.isEmpty else { return ChatPlan.defaults() }
  return list
 }

 func attach(_ clips: TwitchClips,stream hub: StreamHub,feed log: FridayFeed) {
  if twitch == nil { twitch = clips; stream = hub; feed = log }
 }

 var channelLogin: String { (twitch?.channel ?? "").trimmingCharacters(in:CharacterSet(charactersIn:"@ \n")).lowercased() }

 func start() {
  guard twitch?.signedIn == true else { status = "Connect Twitch first (Accounts)."; return }
  loop?.cancel()
  on = true; failures = 0
  startedAt = Date(); lastAny = nil; lastPosted = [:]
  status = "On. Nothing posts until you're live, and the first message waits about \(ChatPlan.gapMinutes) minutes."
  feed?.add("action","Chat helper started")
  loop = Task { [weak self] in
   while !Task.isCancelled {
    guard let self = self, self.on else { return }
    await self.tick()
    try? await Task.sleep(nanoseconds:30_000_000_000)
   }
  }
 }

 func stop() {
  guard on else { return }
  on = false
  loop?.cancel(); loop = nil
  status = "Paused. Nothing will be posted."
  feed?.add("action","Chat helper paused")
 }

 private func tick() async {
  guard let hub = stream else { return }
  await hub.refresh()
  guard hub.liveNow else { status = "On, waiting for you to go live. Nothing posts while you're offline."; return }
  guard let timer = ChatPlan.next(timers,lastPosted:lastPosted,startedAt:startedAt,lastAny:lastAny,posts:postLog,now:Date()) else {
   status = "On and live. Next message is waiting its turn."
   return
  }
  let result = await send(timer,automatic:true)
  if !result.sent {
   failures += 1
   if failures >= 2 { stop(); status = "Stopped after two failures. \(result.note)" }
  } else { failures = 0 }
 }

 // One saved message, now. Also used by the Post now button and by Friday when he asks for it by name.
 @discardableResult func send(_ timer: ChatTimer,automatic: Bool) async -> (sent: Bool,note: String) {
  guard !posting else { return (false,"Already posting one.") }
  guard let tw = twitch, tw.signedIn else { return fail("Connect Twitch first (Accounts).") }
  guard let hub = stream else { return fail("The Stream page isn't ready yet.") }
  if hub.channel == nil || hub.meID.isEmpty { await hub.refresh(force:true) }
  guard let channelID = hub.channel?.id, !hub.meID.isEmpty else { return fail("I couldn't load your channel from Twitch.") }
  let text = ChatPlan.render(timer.text,channel:channelLogin)
  if let problem = ChatPlan.problem(text) { return fail(problem) }
  guard let body = ChatPlan.sendBody(broadcaster:channelID,sender:hub.meID,message:text) else { return fail("Couldn't build the message.") }
  posting = true
  defer { posting = false }
  do {
   let (code,json) = try await tw.call("/chat/messages",method:"POST",body:body)
   let result = ChatPlan.outcome(code:code,json:json)
   if result.sent {
    let now = Date()
    lastPosted[timer.id] = now
    if automatic { lastAny = now; postLog.append(now) }
    status = "Posted “\(timer.name)” at \(now.formatted(date:.omitted,time:.shortened))."
    feed?.add("action","Posted in chat: \(timer.name)")
   } else { status = result.note }
   return result
  } catch {
   return fail("Couldn't reach Twitch: \(error.localizedDescription)")
  }
 }

 private func fail(_ note: String) -> (sent: Bool,note: String) {
  status = note
  return (false,note)
 }

 func add() {
  timers.append(ChatTimer(id:UUID().uuidString,name:"New message",text:"",minutes:30,enabled:false))
 }

 func remove(_ timer: ChatTimer) { timers.removeAll { $0.id == timer.id } }

 func resetToStarters() { timers = ChatPlan.defaults() }

 // Friday's voice tools. She can only post a saved message by name, or turn the helper on or off.
 func voicePost(_ raw: String) async -> String {
  let wanted = raw.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
  let usable = timers.filter { ChatPlan.problem($0.text) == nil }
  guard !usable.isEmpty else { return "There are no saved chat messages yet. Matthew can add them on the Stream page." }
  guard !wanted.isEmpty, let timer = usable.first(where: { $0.name.lowercased() == wanted }) ?? usable.first(where: { $0.name.lowercased().contains(wanted) || wanted.contains($0.name.lowercased()) }) else {
   return "I couldn't find that message. The saved ones are: \(usable.map { $0.name }.joined(separator:", "))."
  }
  let result = await send(timer,automatic:false)
  return result.sent ? "Done. Posted the \(timer.name) message in chat." : result.note
 }

 func voiceSwitch(_ turnOn: Bool) -> String {
  if turnOn {
   if on { return "The chat helper is already on." }
   start()
   return on ? "The chat helper is on. It posts Matthew's saved links and reminders while he is live, starting in about \(ChatPlan.gapMinutes) minutes." : status
  }
  if !on { return "The chat helper is already off." }
  stop()
  return "The chat helper is paused."
 }
}

extension CompanionInterfaceView {
 var hubStreamChat: some View {
  VStack(alignment:.leading,spacing:14) {
   HStack(spacing:10) {
    Text("Chat helper").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
    hubPill(chat.on ? "ON" : "OFF",tint:chat.on ? HubColor.green : HubColor.slate)
    Spacer()
    Button { if chat.on { chat.stop() } else { chat.start() } } label: { Label(chat.on ? "Pause" : "Start",systemImage:chat.on ? "pause.fill" : "play.fill") }
     .buttonStyle(PillButtonStyle(tint:chat.on ? Color.white.opacity(0.12) : Noir.crimson))
   }
   Text("Posts your saved links and reminders in your chat while you're live, from \(stream.meLogin.isEmpty ? "the signed-in Twitch account" : stream.meLogin). It is off every time the app opens, and it only posts your own saved messages.").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.6))
   if !chat.status.isEmpty { Text(chat.status).font(.system(size:12.5,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.8)) }
   VStack(spacing:10) {
    ForEach($chat.timers) { $timer in
     VStack(alignment:.leading,spacing:8) {
      HStack(spacing:10) {
       Toggle("",isOn:$timer.enabled).labelsHidden().toggleStyle(.switch)
       TextField("Name",text:$timer.name).textFieldStyle(.plain).font(.system(size:13.5,weight:.semibold,design:.rounded)).frame(maxWidth:180)
       Spacer()
       Stepper(value:$timer.minutes,in:ChatPlan.minMinutes...ChatPlan.maxMinutes,step:5) { Text("every \(timer.minutes) min").font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.6)) }
       Button { Task { await chat.send(timer,automatic:false) } } label: { Text("Post now") }
        .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12))).disabled(chat.posting || ChatPlan.problem(timer.text) != nil)
       Button { chat.remove(timer) } label: { Image(systemName:"trash") }.buttonStyle(.plain).foregroundStyle(Color.white.opacity(0.5)).help("Delete this message")
      }
      TextField("What should it say? Use {channel} for your channel name.",text:$timer.text,axis:.vertical).lineLimit(1...4).textFieldStyle(.plain)
       .font(.system(size:13,design:.rounded))
       .padding(.horizontal,12).padding(.vertical,9)
       .background(RoundedRectangle(cornerRadius:10,style:.continuous).fill(Color.white.opacity(0.07)))
      if let problem = ChatPlan.problem(timer.text), !timer.text.isEmpty { Text(problem).font(.system(size:11.5,design:.rounded)).foregroundStyle(Noir.crimsonLight) }
     }
     .padding(12)
     .background(RoundedRectangle(cornerRadius:14,style:.continuous).fill(Color.white.opacity(timer.enabled ? 0.06 : 0.025)))
    }
   }
   HStack(spacing:10) {
    Button { chat.add() } label: { Label("Add a message",systemImage:"plus") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    Button { chat.resetToStarters() } label: { Label("Back to the starter messages",systemImage:"arrow.uturn.backward") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   }
   Text("Built-in limits: only while Twitch says you're live, at least \(ChatPlan.gapMinutes) minutes between posts, at most \(ChatPlan.hourlyCap) an hour, each message waits its own number of minutes, and nothing that starts with / or . Check that your Prime wording matches what Twitch offers today.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
  }
  .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
 }
}
