import SwiftUI
import AppKit

// Command Core's shared frame (Matthew's brief, 2026-11-06: "all six tabs should look like parts of ONE unified Mac application", "Friday should feel
// integrated throughout", "every status trustworthy: source and last update, or labeled demo").
// Every tab sits inside this: header (brand, tab title, one honest sentence, source lights), the tab's own content, Friday's slim contextual
// panel, and the collapsible activity & command line drawer. The drawer and Friday's panel keep their open/closed state as you move between tabs.
// Friday's panel shows OBSERVATIONS built from real readings (each names its source); it never calls a model by itself, so it costs no usage.
// "Ask Friday" opens the command line, where a message does go to her brain.

@MainActor final class CoreShellUI: ObservableObject {
 static let shared = CoreShellUI()
 @Published var drawerOpen = false
 @Published var fridayOpen = false
}

struct CoreObservation: Identifiable {
 var id = UUID()
 var tone: Int                     // 0 info, 1 good, 2 attention, 3 urgent
 var text: String                  // one plain sentence
 var why: String                   // what it means / what to do, in plain words
 var source: String                // where the reading came from, with its time
 var actionTitle: String? = nil
 var run: (() -> Void)? = nil
}

struct CoreShell: View {
 var title: String
 var subtitle: String
 var subtitleTone: Int = 0
 var lights: [(String,HackLight,String)]
 var observations: [CoreObservation]
 var newest: String
 var tape: AnyView
 var terminal: AnyView
 var content: AnyView
 @ObservedObject private var ui = CoreShellUI.shared
 @Environment(\.accessibilityReduceMotion) private var reduceMotion

 private func tone(_ t: Int) -> Color {
  switch t { case 1: return CoreStyle.emerald; case 2: return CoreStyle.amber; case 3: return CoreStyle.crimson; default: return CoreStyle.teal }
 }
 private func lightColor(_ l: HackLight) -> Color {
  switch l { case .fresh: return CoreStyle.emerald; case .stale: return CoreStyle.amber; case .failed: return CoreStyle.crimson; case .off: return CoreStyle.dim }
 }

 var body: some View {
  VStack(spacing:0) {
   header
   content.frame(maxWidth:.infinity,maxHeight:.infinity)
   bottomBar
  }
 }

 var header: some View {
  HStack(alignment:.bottom,spacing:14) {
   VStack(alignment:.leading,spacing:3) {
    (Text("Command Core ").foregroundStyle(CoreStyle.crimson) + Text("/ \(title)").foregroundStyle(CoreStyle.ink))
     .font(.system(size:19,weight:.regular,design:.rounded))
    Text(subtitle).font(.system(size:12,design:.rounded)).foregroundStyle(subtitleTone == 0 ? CoreStyle.dim : tone(subtitleTone)).lineLimit(1)
   }
   Spacer(minLength:0)
   HStack(spacing:12) {
    ForEach(Array(lights.enumerated()),id:\.offset) { _,l in
     HStack(spacing:5) {
      Circle().fill(l.1 == .off ? Color.clear : lightColor(l.1)).overlay(Circle().stroke(lightColor(l.1),lineWidth:1)).frame(width:7,height:7)
      Text(l.0).font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim)
     }
     .help(l.2)
    }
   }
  }
  .padding(.horizontal,24).padding(.top,12).padding(.bottom,10)
 }

 // MARK: one slim bottom bar (reference): activity & command line on the left, Friday on the right. Each opens its own panel above it.

 var bottomBar: some View {
  let top = observations.first
  return VStack(spacing:0) {
   if ui.drawerOpen || ui.fridayOpen {
    HStack(alignment:.top,spacing:14) {
     if ui.drawerOpen { VStack(spacing:8) { tape.frame(height:140); terminal }.frame(maxWidth:.infinity) }
     if ui.fridayOpen { fridayList.frame(width:ui.drawerOpen ? 340 : nil).frame(maxWidth:ui.drawerOpen ? 340 : .infinity) }
    }
    .padding(.horizontal,22).padding(.top,10).padding(.bottom,4)
    .transition(.move(edge:.bottom).combined(with:.opacity))
   }
   HStack(spacing:10) {
    Button { withAnimation(reduceMotion ? nil : .easeInOut(duration:0.25)) { ui.drawerOpen.toggle() } } label: {
     HStack(spacing:8) {
      Circle().fill(CoreStyle.emerald).frame(width:6,height:6)
      Text("Activity & Command Line").font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.85))
      Text(newest).font(DeckMono.font(11)).foregroundStyle(CoreStyle.dim).lineLimit(1)
     }
     .contentShape(Rectangle())
    }.buttonStyle(.plain)
    Spacer(minLength:8)
    Button { withAnimation(reduceMotion ? nil : .easeInOut(duration:0.25)) { ui.fridayOpen.toggle() } } label: {
     HStack(spacing:7) {
      Circle().fill(top.map { tone($0.tone) } ?? CoreStyle.dim).frame(width:6,height:6)
      Text(top.map { "Friday: " + $0.text } ?? "Friday").font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.8)).lineLimit(1).frame(maxWidth:300,alignment:.trailing)
     }
     .contentShape(Rectangle())
    }.buttonStyle(.plain)
    Button { withAnimation(reduceMotion ? nil : .easeInOut(duration:0.25)) { ui.drawerOpen = true; ui.fridayOpen = true } } label: {
     Text("Ask Friday ›").font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(CoreStyle.emerald)
    }.buttonStyle(.plain)
   }
   .padding(.horizontal,24).padding(.vertical,9)
  }
  .background(HubTheme.hex(0x0A0A0C))
  .overlay(alignment:.top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height:1) }
 }

 var fridayList: some View {
  VStack(alignment:.leading,spacing:9) {
   HStack(spacing:6) {
    Circle().fill(CoreStyle.crimson).frame(width:7,height:7)
    Text("Friday's read on this tab").font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(CoreStyle.ink)
   }
   if observations.isEmpty { Text("Nothing to flag here. Everything I can read looks normal.").font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.dim) }
   ForEach(observations.prefix(4)) { o in
    HStack(alignment:.top,spacing:8) {
     Circle().fill(tone(o.tone)).frame(width:6,height:6).padding(.top,5)
     VStack(alignment:.leading,spacing:2) {
      Text(o.text).font(.system(size:12.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.ink)
      Text(o.why).font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.68)).fixedSize(horizontal:false,vertical:true)
      Text(o.source).font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
     }
     Spacer(minLength:6)
     if let t = o.actionTitle, let run = o.run {
      Button(action:run) { Text(t).font(.system(size:11.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.teal) }.buttonStyle(.plain)
     }
    }
   }
  }
  .padding(12).frame(maxWidth:.infinity,alignment:.topLeading)
  .background(RoundedRectangle(cornerRadius:12).fill(HubTheme.hex(0x111114)))
  .overlay(RoundedRectangle(cornerRadius:12).stroke(Color.white.opacity(0.07),lineWidth:1))
 }
}

// The one card style for every Command Core tab (reference: compact, dark, hairline border, small sentence-case title).
struct CoreCard<Content: View>: View {
 var title: String
 var icon: String? = nil
 @ViewBuilder var content: Content
 var body: some View {
  VStack(alignment:.leading,spacing:7) {
   HStack(spacing:7) {
    if let icon { Image(systemName:icon).font(.system(size:12.5)).foregroundStyle(CoreStyle.ink.opacity(0.75)) }
    Text(title).font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(CoreStyle.ink)
   }
   content
  }
  .padding(13).frame(maxWidth:.infinity,alignment:.topLeading)
  .background(RoundedRectangle(cornerRadius:11).fill(HubTheme.hex(0x111114)))
  .overlay(RoundedRectangle(cornerRadius:11).stroke(Color.white.opacity(0.065),lineWidth:1))
 }
}

// "MAC CHECKS · GUARD'S OWN" -> "Mac checks · Guard's own": sentence case, with the names that keep their capitals.
func coreTitle(_ s: String) -> String {
 guard s == s.uppercased() else { return s }
 var t = s.lowercased()
 if let f = t.first { t = f.uppercased() + t.dropFirst() }
 for w in ["Mac","Guard","Nmap","USB","GitHub","Friday","CPU","macOS","OWASP","ZAP","Kali","Wireshark","Linux","iPhone","Android","Windows","iOS","Lockdown"] {
  t = t.replacingOccurrences(of:"(?i)\\b\(w)\\b",with:w,options:.regularExpression)
 }
 return t
}

extension CompanionInterfaceView {
 // One call builds the shared frame for any tab.
 func coreFrame(_ title: String,_ subtitle: String,tone: Int = 0,observations: [CoreObservation],content: AnyView) -> some View {
  HackRoomFrame(state:HackRoomState.shared) {
   CoreShell(title:title,subtitle:subtitle,subtitleTone:tone,
             lights:HackSource.allCases.map { s in (s.rawValue,hackLight(s).0,hackLight(s).1) },
             observations:observations,
             newest:hackTape.first.map { "\(deckTapeTime($0.date))  \($0.tag)  \($0.text)" } ?? "quiet: nothing read yet",
             tape:AnyView(hackTapePanel),
             terminal:AnyView(HackCommandLine(brain:FridayBrain.shared,room:HackRoomState.shared,switchboard:Switchboard.shared)),
             content:content)
  }
  .onAppear {
   Task { await meeting.chat.refresh(token:meeting.hasToken ? meeting.savedToken() : nil) }
   CrewSignals.refreshIfStale()
   let g = GuardHub.shared
   if g.results.isEmpty && !g.locked && !g.offline { Task { await g.runChecks() } }
  }
 }

 // Friday's observations from what Guard and the automations actually reported (each one names its source and time).
 func coreObservations() -> [CoreObservation] {
  let g = GuardHub.shared
  var out: [CoreObservation] = []
  let guardWhen = g.lastChecked.map { "Guard check, \(coreAgo($0))" } ?? "Guard check"
  if g.locked {
   out.append(CoreObservation(tone:2,text:"Lockdown is on.",why:"Her hands, screen view, links and posts are off until you press Unlock on the Guard tab.",source:"Guard, now"))
  }
  if g.results.isEmpty && !g.locked {
   out.append(CoreObservation(tone:0,text:"I haven't checked this Mac yet.",why:"Run Guard's checks and I'll tell you what needs a look.",source:"nothing read yet",
    actionTitle:"Run checks",run:{ Task { await GuardHub.shared.runChecks() } }))
  }
  for r in g.results where r.verdict == .warn {
   out.append(CoreObservation(tone:2,text:"\(r.title): needs a look.",why:r.fix.isEmpty ? r.detail : r.fix,source:guardWhen))
  }
  let fresh = g.network.filter { $0.isNew }
  if !fresh.isEmpty {
   out.append(CoreObservation(tone:2,text:"\(fresh.count) new app\(fresh.count == 1 ? " is" : "s are") using the internet: \(fresh.prefix(3).map { $0.name }.joined(separator:", ")).",
    why:"They weren't there at Guard's first look. If you know them, nothing to do; if you don't, tell me and we'll look closer.",source:guardWhen))
  }
  if let runs = ventures.runs {
   let failing = runs.filter { $0.isFailing }
   if !failing.isEmpty {
    out.append(CoreObservation(tone:3,text:"\(failing.count) automation\(failing.count == 1 ? " is" : "s are") failing: \(failing.prefix(2).map { $0.name }.joined(separator:", ")).",
     why:"A failing automation can mean a post or a robot didn't run. The crew can look at it.",source:"GitHub Actions read, \(ventures.lastRefresh == .distantPast ? "just now" : coreAgo(ventures.lastRefresh))"))
   }
  }
  if out.isEmpty, !g.results.isEmpty {
   out.append(CoreObservation(tone:1,text:"Nothing needs attention right now.",why:"Guard's \(g.results.count) checks are fine and no automations are failing.",source:guardWhen))
  }
  return out
 }
}
