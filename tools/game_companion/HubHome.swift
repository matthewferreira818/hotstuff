import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Home uses snapshots already loaded by the app. Opening a crew page does not start a model or microphone.
extension CompanionInterfaceView {
 var hubGreeting: String {
  var calendar = Calendar.current
  calendar.timeZone = TimeZone(identifier:"America/Moncton") ?? calendar.timeZone
  let hour = calendar.component(.hour,from:Date())
  if hour < 12 { return "Good morning, Matthew" }
  if hour < 18 { return "Good afternoon, Matthew" }
  return "Good evening, Matthew"
 }

 var hubHome: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:18) {
    hubHomeNeeds
    hubHomeSection("Your ventures",detail:"Numbers from the loaded snapshots")
    LazyVGrid(columns:[GridItem(.adaptive(minimum:175),spacing:12)],spacing:12) {
     hubHomeVenture(.store,title:"HotsTuff",metric:ventures.store.map { String($0.week) } ?? "—",unit:"visitors · last 7 days",detail:hubStoreHeadline)
     hubHomeVenture(.ecs,title:"East Coast Social",metric:ventures.feed.map { String($0.total) } ?? "—",unit:"published feed posts",detail:hubEcsHeadline)
     hubHomeVenture(.stocks,title:"Stock bot",metric:(stocks.dip ?? stocks.momentum).map { hubMoney($0.value) } ?? "—",unit:"practice-account snapshot",detail:hubStockHeadline)
    }
    hubHomeSystems
    hubHomeCrew
   }
   .padding(.horizontal,hub.compact ? 16 : 32).padding(.top,4).padding(.bottom,24)
  }
  .scrollIndicators(.hidden)
  .background(HubTheme.background)
  .confirmationDialog("Call a board meeting?",isPresented:$meeting.confirmCall) {
   Button(meeting.hasToken ? "Post the call" : "Copy the call") { Task { await meeting.callMeeting() } }
   Button("Cancel",role:.cancel) {}
  } message: { Text(hubCallWords(meeting.meetingNow)) }
 }

 func hubHomeSection(_ title: String,detail: String) -> some View {
  VStack(alignment:.leading,spacing:4) {
   Text(title).font(.system(size:17,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
    .accessibilityAddTraits(.isHeader)
   Text(detail).font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
  }
 }

 var hubHomeNeeds: some View {
  let needs = meeting.needs
  return VStack(alignment:.leading,spacing:8) {
   HStack(spacing:8) {
    Image(systemName:"hand.raised.fill").foregroundStyle(HubTheme.crimson).accessibilityHidden(true)
    Text("Needs you").font(.system(size:17,weight:.semibold,design:.rounded))
     .foregroundStyle(HubTheme.text).accessibilityAddTraits(.isHeader)
    if meeting.board != nil {
     Text(String(needs.count)).font(.system(size:12,weight:.bold,design:.rounded))
      .foregroundStyle(HubTheme.text).padding(.horizontal,8).padding(.vertical,4)
      .background(HubTheme.control,in:Capsule())
    }
    Spacer(minLength:0)
    Button { hubHomeOpenRoom(0) } label: {
     Image(systemName:"arrow.up.right").frame(width:44,height:44)
      .foregroundStyle(HubTheme.subtext).contentShape(Rectangle())
    }
    .buttonStyle(.plain).accessibilityLabel("Open everything waiting for you in the Meeting Room")
    .help("Open the Meeting Room")
   }
   if meeting.board == nil {
    Text(meeting.loading ? "Reading the room…" : "The room hasn't loaded. Open it or use Refresh to try again.")
     .font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.subtext).padding(.bottom,8)
   } else if needs.count == 0 {
    Text("No questions, tasks or pending replies in the loaded room.")
     .font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.subtext).padding(.bottom,8)
   } else {
    // Three real items keep Home short. Open leads to the complete lists.
    let questions = Array(needs.questions.prefix(3))
    let messages = Array(needs.messages.suffix(max(0,3 - questions.count)).reversed())
    let tasks = Array(needs.tasks.prefix(max(0,3 - questions.count - messages.count)))
    ForEach(questions) { item in
     hubHomeNeedRow(kind:"Question",text:item.text,owner:MeetingData.who(item.owner),opened:item.id)
    }
    ForEach(messages) { message in
     hubHomeNeedRow(kind:"Reply",text:message.text,owner:message.author,opened:"m\(message.id)")
    }
    ForEach(tasks) { item in
     hubHomeNeedRow(kind:"To-do",text:item.text,owner:"",opened:item.id)
    }
    if needs.count > 3 {
     Button { hubHomeOpenRoom(0) } label: {
      Text("See all \(needs.count) in the room").font(.system(size:12,weight:.semibold,design:.rounded))
       .foregroundStyle(HubTheme.text).frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
     }.buttonStyle(.plain)
    }
   }
   if meeting.board != nil {
    Text("From the loaded board and recent messages; refresh to check for changes.")
     .font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
   }
  }
  .padding(.horizontal,18).padding(.top,8).padding(.bottom,14)
  .frame(maxWidth:.infinity,alignment:.leading)
  .background(HubTheme.card,in:RoundedRectangle(cornerRadius:20))
  .overlay(RoundedRectangle(cornerRadius:20).stroke(HubTheme.line,lineWidth:1))
 }

 func hubHomeNeedRow(kind: String,text: String,owner: String,opened: String) -> some View {
  let name = MeetingData.display(MeetingData.canonical(owner) ?? owner)
  return Button {
   meeting.opened.insert(opened)
   hubHomeOpenRoom(0)
  } label: {
   HStack(alignment:.center,spacing:10) {
    VStack(alignment:.leading,spacing:3) {
     Text(name.isEmpty ? kind : "\(kind) · \(name)")
      .font(.system(size:11.5,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.subtext)
     Text(MeetingData.brief(text)).font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.text)
      .lineLimit(2).multilineTextAlignment(.leading)
    }
    Spacer(minLength:4)
    Image(systemName:"chevron.right").font(.system(size:10,weight:.semibold)).foregroundStyle(HubTheme.subtext)
   }
   .padding(.vertical,4).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
  }
  .buttonStyle(.plain).accessibilityLabel("\(kind)\(name.isEmpty ? "" : " from \(name)"): \(text)")
  .accessibilityHint("Opens the full item in the Meeting Room")
 }

 func hubHomeVenture(_ section: HubSection,title: String,metric: String,unit: String,detail: String) -> some View {
  Button { hubSelect(section) } label: {
   VStack(alignment:.leading,spacing:7) {
    HStack(spacing:8) {
     Image(systemName:section.icon).foregroundStyle(section.tint).accessibilityHidden(true)
     Text(title).foregroundStyle(HubTheme.text).lineLimit(2)
     Spacer(minLength:0)
     Image(systemName:"arrow.up.right").foregroundStyle(HubTheme.subtext).accessibilityHidden(true)
    }
    .font(.system(size:13,weight:.semibold,design:.rounded))
    Text(metric).font(.system(size:25,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text)
     .lineLimit(1).minimumScaleFactor(0.65).padding(.top,3)
    Text(unit).font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
    Text(detail).font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
     .lineLimit(2).multilineTextAlignment(.leading)
   }
   .padding(16).frame(maxWidth:.infinity,minHeight:158,alignment:.topLeading)
   .background(HubTheme.card,in:RoundedRectangle(cornerRadius:20))
   .overlay(RoundedRectangle(cornerRadius:20).stroke(HubTheme.line,lineWidth:1))
   .contentShape(RoundedRectangle(cornerRadius:20))
  }
  .buttonStyle(.plain).accessibilityLabel("\(title), \(metric) \(unit). \(detail)")
  .accessibilityHint("Opens \(section.title)")
 }

 var hubHomeSystems: some View {
  Button { hubSelect(.systems) } label: {
   HStack(spacing:10) {
    Image(systemName:ventures.alerts.isEmpty ? "gearshape.2" : "exclamationmark.triangle")
     .foregroundStyle(ventures.alerts.isEmpty ? HubTheme.subtext : HubTheme.amber).accessibilityHidden(true)
    VStack(alignment:.leading,spacing:3) {
     Text("Systems").font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
     Text(hubSystemsHeadline).font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
      .lineLimit(2).multilineTextAlignment(.leading)
    }
    Spacer(minLength:0)
    Image(systemName:"chevron.right").font(.system(size:11,weight:.semibold)).foregroundStyle(HubTheme.subtext)
   }
   .padding(.horizontal,16).padding(.vertical,10).frame(maxWidth:.infinity,minHeight:60,alignment:.leading)
   .background(HubTheme.card,in:RoundedRectangle(cornerRadius:16))
   .overlay(RoundedRectangle(cornerRadius:16).stroke(HubTheme.line,lineWidth:1))
  }
  .buttonStyle(.plain).accessibilityLabel("Systems. \(hubSystemsHeadline)").accessibilityHint("Opens Systems")
 }

 var hubHomeCrew: some View {
  VStack(alignment:.leading,spacing:10) {
   hubHomeSection("Your crew",detail:"Claude and Roxy's room tabs; Friday's voice page")
   LazyVGrid(columns:[GridItem(.adaptive(minimum:160),spacing:10)],spacing:10) {
    hubHomeCrewMember("Claude",role:"Project lead",tint:HubTheme.orbClaude,tab:1)
    hubHomeCrewMember(MeetingData.display("GPT"),role:"Design & build",tint:HubTheme.orbRoxy,tab:2)
    hubHomeCrewMember("Friday",role:"Voice companion",tint:HubTheme.orbFriday,tab:nil)
   }
   Button { meeting.confirmCall = true } label: {
    Label("Call a board meeting",systemImage:"person.3")
     .font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
     .frame(maxWidth:.infinity,minHeight:44)
     .background(HubTheme.control,in:RoundedRectangle(cornerRadius:12))
     .overlay(RoundedRectangle(cornerRadius:12).stroke(HubTheme.controlOutline,lineWidth:1))
   }
   .buttonStyle(.plain).disabled(meeting.sending || DesignPreview.enabled)
   .accessibilityHint("Asks for confirmation before posting or copying a call. This is not a live call.")
  }
 }

 func hubHomeCrewMember(_ name: String,role: String,tint: Color,tab: Int?) -> some View {
  Button {
   if let tab = tab { hubHomeOpenRoom(tab) } else { hubSelect(.friday) }
  } label: {
   HStack(spacing:10) {
    Circle().fill(RadialGradient(colors:[tint.opacity(0.95),tint.opacity(0.25),HubTheme.card],center:.topLeading,startRadius:1,endRadius:45))
     .frame(width:36,height:36).overlay(Circle().stroke(tint.opacity(0.4),lineWidth:1)).accessibilityHidden(true)
    VStack(alignment:.leading,spacing:3) {
     Text(name).font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
     Text(role).font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
    }
    Spacer(minLength:0)
   }
   .padding(12).frame(maxWidth:.infinity,minHeight:64,alignment:.leading)
   .background(HubTheme.card,in:RoundedRectangle(cornerRadius:16))
   .overlay(RoundedRectangle(cornerRadius:16).stroke(HubTheme.line,lineWidth:1))
  }
  .buttonStyle(.plain).accessibilityLabel("\(name), \(role)")
  .accessibilityHint(tab == nil ? "Opens Friday without starting a conversation" : "Opens \(name)'s Meeting Room tab")
 }

 func hubHomeOpenRoom(_ tab: Int) {
  meeting.composing = false
  meeting.fridayPrivate = false
  meeting.tab = tab
  hubSelect(.meeting)
 }

 var hubStockHeadline: String {
  guard let robot = stocks.dip ?? stocks.momentum else { return stocks.loading ? "Loading practice snapshots…" : "Practice snapshot unavailable · open to retry" }
  let snapshot = robot.updated.map { "Snapshot \(hubAgo($0))" } ?? "Snapshot time unavailable"
  return "\(robot.name) · \(snapshot)"
 }

 var hubStoreHeadline: String {
  guard let store = ventures.store else { return ventures.loading ? "Loading visitor counts…" : "Visitor counts unavailable · open to retry" }
  return "\(store.today) visitors today · public store counters"
 }

 var hubEcsHeadline: String {
  guard let feed = ventures.feed else { return ventures.loading ? "Loading the feed…" : "Feed unavailable · open to retry" }
  if let days = feed.streakDays() { return "\(days)-day store-feed streak" }
  return "Latest feed post: \(feed.last.isEmpty ? "date unavailable" : feed.last)"
 }

 var hubSystemsHeadline: String {
  guard let runs = ventures.runs else { return ventures.loading ? "Loading automation status…" : "Automation status unavailable · open to retry" }
  let failures = runs.filter { $0.isFailing }.count
  let running = runs.filter { $0.isRunning }.count
  var parts = ["\(runs.count) latest runs", "\(failures) failing"]
  if running > 0 { parts.append("\(running) in progress") }
  if ventures.catalog?.isStale() == true { parts.append("catalog needs refresh") }
  return parts.joined(separator:" · ")
 }

 // Existing summaries used by other pages.
 var hubGameHeadline: String {
  if live.running { return "Friday is live" }
  if live.sees == 0 { return "All screens · ready" }
  return c.sharing ? "Window chosen · ready" : "No window chosen yet"
 }
 var hubAccountsHeadline: String {
  let connected = [live.hasKey,clips.signedIn,sales.hasKey,meeting.hasToken].filter { $0 }.count
  return "\(connected) of 4 logins connected"
 }
}
