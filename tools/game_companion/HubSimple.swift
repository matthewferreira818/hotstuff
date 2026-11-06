import SwiftUI
import AppKit

// Simple mode (2026-11-06): the default. One orb, one big Talk button, at most three cards, four tabs and a More menu where every
// other page lives with a one-line "what this is". Plain words only. Advanced mode (More menu) brings back the full Signal Deck.
// Nothing here starts anything by itself: the Talk button does what the dock's button did.
extension CompanionInterfaceView {
 static let simpleTabs: [HubSection] = [.home,.friday,.store,.meeting]
 static let simpleMore: [HubSection] = [.stocks,.ecs,.crewStation,.memory,.hacking,.helper,.shield,.realFake,.lab,.council,.launchpad,.game,.stream,.accounts,.systems]

 func simpleName(_ section: HubSection) -> String {
  switch section {
  case .meeting: return "Messages"
  case .stocks: return "Practice stocks"
  case .ecs: return "East Coast Social"
  case .crewStation: return "Crew station"
  case .memory: return "What Friday remembers"
  case .hacking: return "Live activity"
  case .shield: return "Safety checks"
  case .realFake: return "Real or fake?"
  case .lab: return "Learn to stay safe"
  case .launchpad: return "Shortcuts"
  case .stream: return "Streaming"
  case .systems: return "Daily jobs"
  default: return section.title
  }
 }

 func simpleBlurb(_ section: HubSection) -> String {
  switch section {
  case .home: return "Everything important, in one place."
  case .friday: return "Talk to Friday, your voice helper."
  case .store: return "How many people visit your store."
  case .meeting: return "Your crew's messages."
  case .stocks: return "Practice-money robots. No real money, ever."
  case .ecs: return "Your daily posting business."
  case .crewStation: return "See who is busy, resting or away."
  case .memory: return "What Friday remembers. Keep, edit or forget."
  case .hacking: return "A live feed of what your robots and helpers are doing."
  case .helper: return "Give Friday a job to do on your Mac."
  case .shield: return "Check your Mac and lock things down."
  case .realFake: return "Paste a message and Friday points out the red flags."
  case .lab: return "Short lessons on staying safe online."
  case .council: return "Three AIs talk over your question (test mode)."
  case .launchpad: return "Open the sites and apps you use."
  case .game: return "What Friday sees while you play."
  case .stream: return "Your Twitch setup."
  case .accounts: return "What's connected. No passwords shown."
  case .systems: return "Are your daily jobs running?"
  default: return section.blurb
  }
 }

 // MARK: top bar

 var simpleTopBar: some View {
  HStack(spacing:hub.compact ? 6 : 12) {
   Button { hubSelect(.home) } label: {
    HStack(spacing:5) { Text("The").foregroundStyle(HubTheme.text); Text("Helm").foregroundStyle(HubTheme.green) }
     .font(.system(size:19,weight:.bold,design:.rounded))
   }.buttonStyle(.plain).accessibilityLabel("The Helm Home")
   HStack(spacing:4) { ForEach(Self.simpleTabs) { section in simpleTab(section) } }
   simpleMoreMenu
   Spacer(minLength:6)
   if c.tab == 0 && live.running {
    HStack(spacing:6) { Circle().fill(Noir.crimsonLight).frame(width:8,height:8); Text("Friday is listening").font(.system(size:12,weight:.semibold)) }
     .foregroundStyle(HubTheme.text).padding(.horizontal,12).frame(height:32).background(Capsule().fill(Noir.crimson.opacity(0.35)))
   }
   deckIconButton("arrow.clockwise",label:"Refresh everything (Command-R)",spinning:hubAnyLoading) { Task { await hubRefreshAll() } }
    .keyboardShortcut("r",modifiers:.command).disabled(hubAnyLoading)
   deckIconButton("slider.horizontal.3",label:"Settings (Command-comma)") { c.showPanel = true }
    .keyboardShortcut(",",modifiers:.command)
  }
  .padding(.horizontal,hub.compact ? 12 : 24).frame(height:64)
  .background(HubTheme.sidebar)
  .overlay(alignment:.bottom) { Rectangle().fill(HubTheme.line).frame(height:1) }
 }

 func simpleTab(_ section: HubSection) -> some View {
  let on = hub.section == section
  let index = (Self.simpleTabs.firstIndex(of:section) ?? 0) + 1
  return Button { if section == .meeting { meeting.tab = 6 }; hubSelect(section) } label: {
   Text(simpleName(section)).lineLimit(1).fixedSize()
    .font(.system(size:15,weight:on ? .semibold : .medium))
    .foregroundStyle(on ? HubTheme.text : HubTheme.subtext)
    .padding(.horizontal,hub.compact ? 10 : 16).frame(height:42)
    .background(on ? HubTheme.card : Color.clear,in:RoundedRectangle(cornerRadius:10))
    .overlay(RoundedRectangle(cornerRadius:10).stroke(on ? HubTheme.controlOutline : Color.clear,lineWidth:1))
    .contentShape(Rectangle())
  }
  .buttonStyle(.plain).accessibilityLabel(simpleName(section)).accessibilityAddTraits(on ? .isSelected : [])
  .keyboardShortcut(KeyEquivalent(Character(String(index))),modifiers:.command)
 }

 var simpleMoreMenu: some View {
  let inMore = Self.simpleMore.contains(hub.section)
  return Menu {
   ForEach(Self.simpleMore) { section in
    Button { hubSelect(section) } label: { Label("\(simpleName(section))  ·  \(simpleBlurb(section))",systemImage:section.icon) }
   }
   Divider()
   Button { hub.tourStep = 0; hubSelect(.home) } label: { Label("Show me around",systemImage:"questionmark.circle") }
   Button { c.showPanel = true } label: { Label("Settings",systemImage:"slider.horizontal.3") }
   Button { hub.simple = false } label: { Label("Advanced mode: show everything (full Signal Deck)",systemImage:"switch.2") }
  } label: {
   HStack(spacing:5) { Text("More").font(.system(size:15,weight:inMore ? .semibold : .medium)); Image(systemName:"chevron.down").font(.system(size:10,weight:.bold)) }
    .foregroundStyle(inMore ? HubTheme.text : HubTheme.subtext)
    .padding(.horizontal,16).frame(height:42)
    .background(inMore ? HubTheme.card : Color.clear,in:RoundedRectangle(cornerRadius:10))
    .overlay(RoundedRectangle(cornerRadius:10).stroke(inMore ? HubTheme.controlOutline : HubTheme.line,lineWidth:1))
  }
  .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
  .accessibilityLabel("More: the rest of the app, the tour and Advanced mode")
 }

 // MARK: Home

 var simpleGreetingLine: String {
  let cards = deckOkCards
  if meeting.threadFailed { return GitHubRead.limitMessage().map { "I can't see what needs you. \($0)" } ?? "Couldn't reach your crew's messages, so I can't say what needs you." }
  if meeting.messages.isEmpty { return meeting.loading ? "Checking in with the crew…" : "Tap Refresh to check in with the crew." }
  return cards.isEmpty ? "Nothing is waiting for you right now." : "\(cards.count) \(cards.count == 1 ? "thing is" : "things are") waiting for you."
 }

 var simpleHome: some View {
  GeometryReader { geo in
   let narrow = geo.size.width < 760
   let orb: CGFloat = geo.size.height < 760 ? 88 : 120
   ScrollView {
   VStack(spacing:10) {
    VStack(spacing:2) {
     Text(hubGreeting).font(.system(size:28,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text)
     Text(simpleGreetingLine).font(.system(size:15)).foregroundStyle(HubTheme.subtext)
    }
    TimelineView(.animation(minimumInterval:1.0/30.0,paused:reduceMotion)) { timeline in
     let now = timeline.date
     VStack(spacing:0) {
      FridayOrb(state:orbState(at:now),t:now.timeIntervalSinceReferenceDate,level:orbLevel(at:now),size:orb,animated:!reduceMotion,showsPicker:false)
      Text(deckStateWords(orbState(at:now))).font(.system(size:13)).foregroundStyle(HubTheme.subtext)
     }
    }
    .frame(height:orb * 1.42)
    HStack(spacing:8) {
     Button { mainAction() } label: {
      HStack(spacing:10) {
       Text(live.running || c.listening ? "⏹" : "🎙️").font(.system(size:22))
       Text(live.running || c.listening ? "Stop talking" : "Talk to Friday").font(.system(size:20,weight:.semibold,design:.rounded))
      }
      .foregroundStyle(HubTheme.background)
      .frame(width:300,height:60)
      .background(live.running || c.listening ? HubTheme.amber : HubTheme.green,in:RoundedRectangle(cornerRadius:16))
     }
     .buttonStyle(.plain).disabled(DesignPreview.enabled)
     .accessibilityLabel(live.running ? "Stop talking to Friday" : "Talk to Friday")
     .help(live.running ? "Stop the live session" : "Starts Friday. While she is on, she hears your mic and sees your screens.")
     simpleHelp("talk","Tap once to wake Friday, then just speak. Tap again to stop. While she is on she can hear you and see your screens.")
    }
    MoneyMoveCard()
    Group {
     if narrow { VStack(spacing:12) { simpleNeedsCard; simpleTodayCard; simpleBusinessCard } }
     else { HStack(alignment:.top,spacing:12) { simpleNeedsCard; simpleTodayCard; simpleBusinessCard } }
    }
    Spacer(minLength:0)
   }
   .padding(.horizontal,hub.compact ? 16 : 32).padding(.top,18).padding(.bottom,16)
   .frame(maxWidth:.infinity)
   }
   .scrollIndicators(.hidden)
  }
  .background(HubTheme.background)
  .onAppear { if !UserDefaults.standard.bool(forKey:"hub.tourSeen") && hub.tourStep < 0 { hub.tourStep = 0 } }
  .confirmationDialog("Call a board meeting?",isPresented:$meeting.confirmCall) {
   Button(meeting.hasToken ? "Post the call" : "Copy the call") { Task { await meeting.callMeeting() } }
   Button("Cancel",role:.cancel) {}
  } message: { Text(hubCallWords(meeting.meetingNow)) }
 }

 func simpleHelp(_ id: String,_ text: String) -> some View {
  Button { hub.helpOpen = hub.helpOpen == id ? "" : id } label: {
   Text("?").font(.system(size:13,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.subtext)
    .frame(width:26,height:26).overlay(Circle().stroke(HubTheme.controlOutline,lineWidth:1))
  }
  .buttonStyle(.plain).accessibilityLabel("What is this?")
  .popover(isPresented:Binding(get:{ hub.helpOpen == id },set:{ if !$0 && hub.helpOpen == id { hub.helpOpen = "" } })) {
   Text(text).font(.system(size:14)).padding(14).frame(width:260,alignment:.leading).fixedSize(horizontal:false,vertical:true)
  }
 }

 func simpleCard<Content: View>(_ title: String,help: String,@ViewBuilder _ content: () -> Content) -> some View {
  VStack(alignment:.leading,spacing:10) {
   HStack { Text(title).font(.system(size:17,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text); Spacer(minLength:0); simpleHelp(title,help) }
   content()
   Spacer(minLength:0)
  }
  .padding(14).frame(maxWidth:.infinity,minHeight:150,alignment:.topLeading)
  .background(HubTheme.card,in:RoundedRectangle(cornerRadius:16))
  .overlay(RoundedRectangle(cornerRadius:16).stroke(HubTheme.line,lineWidth:1))
 }

 // 1. Needs you: one plain sentence per real request. "Yes" opens the reply box with a yes already typed (Matthew presses Post);
 // nothing is sent from here. "Not now" hides it until the app is closed.
 var simpleNeedsCard: some View {
  let cards = meeting.threadFailed ? [] : Array(deckOkCards.prefix(2))
  return simpleCard("Needs you",help:"Things the crew is waiting on you for. Yes opens a reply with a yes typed in; you still press Post. Not now hides it for today.") {
   if meeting.threadFailed {
    Text(GitHubRead.limitMessage() ?? "Unknown right now (couldn't reach your crew's messages).").font(.system(size:15)).foregroundStyle(HubTheme.amber)
   } else if cards.isEmpty {
    Text(meeting.messages.isEmpty ? "The room hasn't loaded yet." : "Nothing right now. Enjoy it.").font(.system(size:15)).foregroundStyle(HubTheme.subtext)
   }
   ForEach(cards) { message in
    let body = message.text.drop { $0 != ":" }.dropFirst().trimmingCharacters(in:.whitespacesAndNewlines)
    VStack(alignment:.leading,spacing:6) {
     Text(MeetingData.brief(body,limit:90)).font(.system(size:14,weight:.medium)).foregroundStyle(HubTheme.text).lineLimit(3).fixedSize(horizontal:false,vertical:true)
     HStack(spacing:8) {
      Button { meeting.draft = "Yes, go ahead."; meeting.compose(to:0); hubHomeOpenRoom(5) } label: { Text("Yes").font(.system(size:13,weight:.semibold)).foregroundStyle(HubTheme.background).padding(.horizontal,14).frame(height:30).background(HubTheme.green,in:Capsule()) }.buttonStyle(.plain)
      Button { hub.dismissed.insert(message.id) } label: { Text("Not now").font(.system(size:13,weight:.medium)).foregroundStyle(HubTheme.text).padding(.horizontal,14).frame(height:30).overlay(Capsule().stroke(HubTheme.controlOutline,lineWidth:1)) }.buttonStyle(.plain)
     }
    }
   }
   Text(meeting.threadFailed ? (GitHubRead.limitMessage() != nil ? "" : "unknown (couldn't reach your crew's messages)") : (meeting.threadAt.map { "as of \(crewChatTime($0)), from your crew's messages" } ?? "loading from your crew's messages…")).font(.system(size:11)).foregroundStyle(HubTheme.subtext)
  }
 }

 // The robots carry their own snapshot times, so the newest one is the honest "as of". No snapshots at all means unknown.
 var simpleRobotsAsOf: String {
  let newest = deckRobots.compactMap { $0.robot?.updated }.max()
  if let newest = newest { return "latest check-in \(crewChatTime(newest)), from the robots' public pages" }
  return stocks.loading ? "loading from the robots' public pages…" : "unknown (couldn't reach the robots' public pages)"
 }

 // 2. Today: plain words about the crew.
 var simpleTodayCard: some View {
  let crew = deckCrew
  let working = crew.filter { $0.state == .working && $0.kind != .friday && $0.kind != .robot }.map { $0.name }
  let robotsRunning = crew.filter { $0.state == .working && $0.kind == .robot }.count
  let failing = crew.filter { $0.state == .failing }.map { $0.name }
  let robots = crew.filter { $0.kind == .robot }
  return simpleCard("Today",help:"A quick look at what your helpers and practice robots are doing. Real data from the room and GitHub.") {
   if crew.count <= 1 && meeting.messages.isEmpty { Text("Loading what everyone is up to…").font(.system(size:15)).foregroundStyle(HubTheme.subtext) }
   else {
    Text(meeting.threadFailed ? "Who is working: unknown. \(GitHubRead.limitMessage() ?? "Couldn't reach your crew's messages.")" : working.isEmpty ? "Nobody is in the middle of a job right now." : "Working now: " + working.prefix(3).joined(separator:", ") + (working.count > 3 ? " and \(working.count - 3) more" : "") + ".")
     .font(.system(size:14)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
    if !robots.isEmpty {
     Text("\(robots.filter { $0.state != .unknown }.count) of \(robots.count) practice robots have checked in" + (robotsRunning > 0 ? ", \(robotsRunning) running now." : ".")).font(.system(size:14)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
     Text(simpleRobotsAsOf).font(.system(size:11)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
    }
    if !failing.isEmpty { Text("Needs a look: \(failing.joined(separator:", ")) hit a problem.").font(.system(size:14,weight:.semibold)).foregroundStyle(HubTheme.amber) }
    Button { hubSelect(.crewStation) } label: { Text("See who's who ›").font(.system(size:13,weight:.medium)).foregroundStyle(HubTheme.teal) }.buttonStyle(.plain)
   }
  }
 }

 // 3. Your businesses: real numbers only, each with "as of <time>, from <source>". A failed read says unknown, never the last good value.
 func simpleAsOf(_ date: Date?,_ source: String,failed: Bool) -> String {
  if failed { return "unknown (couldn't reach \(source))" }
  guard let date = date else { return "loading from \(source)…" }
  return "as of \(crewChatTime(date)), from \(source)"
 }

 // Orders come only from Stripe's read-only key (SalesHub). With no key there is no honest order number, so it says so.
 var simpleOrdersLine: (String,String) {
  if !sales.hasKey { return ("Orders: not tracked yet","Stripe isn't connected to The Helm") }
  guard let s = sales.sales else { return ("Orders: unknown","couldn't read Stripe yet") }
  let n = s.month.orders
  let when = sales.lastRefresh == .distantPast ? "" : "as of \(crewChatTime(sales.lastRefresh)), "
  return (n == 0 ? "Orders (30 days): none yet · Goal: first sale" : "Orders (30 days): \(n)", when + "from Stripe" + (s.testMode ? " (test mode)" : ""))
 }

 var simpleBusinessCard: some View {
  simpleCard("Your businesses",help:"Your store and East Coast Social at a glance. Tap a line to open it. Under every number: when it was read and where from.") {
   Button { hubSelect(.store) } label: {
    VStack(alignment:.leading,spacing:2) {
     Text("HotsTuff store").font(.system(size:13)).foregroundStyle(HubTheme.subtext)
     Text(ventures.store.map { "\($0.week) visitors this week" } ?? (ventures.storeFailed ? "Visitors: unknown" : "Loading…")).font(.system(size:16,weight:.semibold)).foregroundStyle(HubTheme.text)
     Text(simpleAsOf(ventures.storeAt,"GoatCounter",failed:ventures.storeFailed)).font(.system(size:11)).foregroundStyle(HubTheme.subtext)
     Text(simpleOrdersLine.0).font(.system(size:14,weight:.medium)).foregroundStyle(HubTheme.text).padding(.top,3)
     Text(simpleOrdersLine.1).font(.system(size:11)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
    }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
   }.buttonStyle(.plain)
   Button { hubSelect(.ecs) } label: {
    VStack(alignment:.leading,spacing:2) {
     Text("East Coast Social").font(.system(size:13)).foregroundStyle(HubTheme.subtext)
     Text(ventures.feed.map { "\($0.total) cards on the site feed" } ?? (ventures.feedFailed ? "Site feed: unknown" : "Loading…")).font(.system(size:16,weight:.semibold)).foregroundStyle(HubTheme.text)
     Text(simpleAsOf(ventures.feedAt,"the site feed",failed:ventures.feedFailed)).font(.system(size:11)).foregroundStyle(HubTheme.subtext)
    }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
   }.buttonStyle(.plain)
  }
 }

 // MARK: first-run tour

 var simpleTourSteps: [(String,String)] { [
  ("This is Friday","She's your voice helper. Tap the big green Talk button and just speak."),
  ("What needs you","Anything waiting on your OK shows up here in plain words, with Yes and Not now."),
  ("Today","A quick look at what your helpers and practice robots are doing."),
  ("Your businesses","Your store and East Coast Social at a glance. Tap one to open it."),
  ("More is your toolbox","Everything else lives under More. Choose \"Show me around\" there to see this again, or switch to Advanced mode for the full view."),
 ] }

 var simpleTour: some View {
  let steps = simpleTourSteps
  let step = min(hub.tourStep,steps.count - 1)
  func finish() { UserDefaults.standard.set(true,forKey:"hub.tourSeen"); hub.tourStep = -1 }
  return ZStack {
   Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { }
   VStack(alignment:.leading,spacing:12) {
    Text("\(step + 1) of \(steps.count)").font(.system(size:12,weight:.medium,design:.monospaced)).foregroundStyle(HubTheme.subtext)
    Text(steps[step].0).font(.system(size:24,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text)
    Text(steps[step].1).font(.system(size:16)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
    HStack {
     Button { finish() } label: { Text("Skip").font(.system(size:14,weight:.medium)).foregroundStyle(HubTheme.subtext).padding(.horizontal,10).frame(height:40) }.buttonStyle(.plain)
     Spacer()
     Button { if step >= steps.count - 1 { finish() } else { hub.tourStep = step + 1 } } label: {
      Text(step >= steps.count - 1 ? "Got it" : "Next").font(.system(size:15,weight:.semibold)).foregroundStyle(HubTheme.background).padding(.horizontal,22).frame(height:42).background(HubTheme.green,in:Capsule())
     }.buttonStyle(.plain).keyboardShortcut(.defaultAction)
    }
   }
   .padding(24).frame(width:400)
   .background(HubTheme.card,in:RoundedRectangle(cornerRadius:18))
   .overlay(RoundedRectangle(cornerRadius:18).stroke(HubTheme.controlOutline,lineWidth:1))
  }
  .accessibilityAddTraits(.isModal)
 }
}


// Messages in Simple mode opens on the crew chat only. Everything else (other views, a single chat) hides behind ONE Filter button.
extension CompanionInterfaceView {
 var simpleMessagesBar: some View {
  HStack(spacing:10) {
   Menu {
    Button { meeting.lcFilter = ""; meeting.tab = 6 } label: { Label("Everyone",systemImage:meeting.lcFilter.isEmpty && meeting.tab == 6 ? "checkmark" : "person.3") }
    ForEach(meeting.lcNames,id:\.self) { name in
     Button { meeting.lcFilter = name; meeting.tab = 6 } label: { Label(name,systemImage:meeting.lcFilter == name && meeting.tab == 6 ? "checkmark" : "person") }
    }
    Divider()
    Button { meeting.lcFilter = ""; meeting.tab = 0 } label: { Label("What needs you",systemImage:"hand.raised") }
    Button { meeting.lcFilter = ""; meeting.tab = 1 } label: { Label("Claude's work",systemImage:"person.text.rectangle") }
    Button { meeting.lcFilter = ""; meeting.tab = 2 } label: { Label("\(MeetingData.display("GPT"))'s work",systemImage:"person.text.rectangle") }
    Button { meeting.lcFilter = ""; meeting.tab = 3 } label: { Label("Friday's work",systemImage:"waveform") }
    Button { meeting.lcFilter = ""; meeting.tab = 4 } label: { Label("The plan board",systemImage:"list.bullet.rectangle") }
    Button { meeting.lcFilter = ""; meeting.tab = 5 } label: { Label("Write a message / old thread",systemImage:"square.and.pencil") }
   } label: {
    HStack(spacing:6) {
     Image(systemName:"line.3.horizontal.decrease.circle")
     Text(meeting.tab == 6 ? (meeting.lcFilter.isEmpty ? "Filter" : "Filter: \(meeting.lcFilter)") : "Filter").font(.system(size:14,weight:.medium))
    }
    .foregroundStyle(HubTheme.text).padding(.horizontal,14).frame(height:38)
    .overlay(RoundedRectangle(cornerRadius:10).stroke(HubTheme.controlOutline,lineWidth:1))
   }
   .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
   .accessibilityLabel("Filter: pick one chat or another view")
   if meeting.tab != 6 {
    Button { meeting.lcFilter = ""; meeting.tab = 6 } label: { Label("Back to the chat",systemImage:"chevron.left").font(.system(size:14,weight:.medium)).foregroundStyle(HubTheme.green) }.buttonStyle(.plain)
   }
   Spacer(minLength:8)
   Button { Task { await meeting.refresh(force:true) } } label: {
    Label(meeting.loading || { if case .loading = meeting.chat.status { return true }; return false }() ? "Refreshing…" : "Refresh",systemImage:"arrow.clockwise")
     .font(.system(size:14,weight:.medium)).foregroundStyle(HubTheme.text).padding(.horizontal,14).frame(height:38)
     .overlay(RoundedRectangle(cornerRadius:10).stroke(HubTheme.controlOutline,lineWidth:1))
   }.buttonStyle(.plain).disabled(meeting.loading)
  }
 }
}


// Friday's page in Simple mode: the orb, then the chat box (typing is the main door), then ONE Voice button. Voice, hands and clip
// controls (and the "Google Live" pill) appear only after he opens Voice, or while voice is actually on.
extension CompanionInterfaceView {
 var simpleFriday: some View {
  GeometryReader { geo in
   let small = geo.size.height < 700
   ScrollView {
    VStack(spacing:14) {
     orbSection(small ? 110 : 150).padding(.top,6)
     if live.running { captions }
     FridayChatBox(compact:small).frame(maxWidth:640).padding(.horizontal,22)
     FridayMeSection(reduceMotion:reduceMotion).frame(maxWidth:640).padding(.horizontal,22)
     VStack(spacing:10) {
      Button { withAnimation(.easeOut(duration:0.2)) { hub.voiceOpen.toggle() } } label: {
       HStack(spacing:8) {
        Image(systemName:"waveform")
        Text(live.running ? "Voice is on" : "Voice").font(.system(size:15,weight:.medium))
        Image(systemName:hub.voiceOpen || live.running ? "chevron.up" : "chevron.down").font(.system(size:10,weight:.bold))
       }
       .foregroundStyle(HubTheme.text).padding(.horizontal,18).frame(height:42)
       .overlay(RoundedRectangle(cornerRadius:12).stroke(live.running ? HubTheme.green : HubTheme.controlOutline,lineWidth:1))
      }
      .buttonStyle(.plain).accessibilityLabel("Voice, hands and clip controls").accessibilityValue(hub.voiceOpen || live.running ? "open" : "closed")
      if hub.voiceOpen || live.running {
       if live.running { modePill }
       controlBar(compact:true)
       seesRow
       Text("Voice shares your microphone and screens with Google while it is on.").font(.system(size:12)).foregroundStyle(HubTheme.subtext)
      }
     }
     HStack(alignment:.top,spacing:12) {
      deckDoingCard
      deckMemoryCard
      if !hub.compact { deckMusicCard }
     }
     .padding(.horizontal,22)
     SwitchboardPanel(compact:true).padding(.horizontal,22).padding(.bottom,14)
    }
    .frame(maxWidth:.infinity)
   }
   .scrollIndicators(.hidden)
  }
 }
}
