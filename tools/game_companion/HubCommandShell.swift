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
   fridayPanel
   drawer
  }
 }

 var header: some View {
  HStack(alignment:.bottom,spacing:14) {
   VStack(alignment:.leading,spacing:3) {
    (Text("Command Core ").foregroundStyle(CoreStyle.crimson) + Text("/ \(title)").foregroundStyle(CoreStyle.ink))
     .font(.system(size:23,weight:.regular,design:.rounded))
    Text(subtitle).font(.system(size:13.5,design:.rounded)).foregroundStyle(subtitleTone == 0 ? CoreStyle.dim : tone(subtitleTone)).lineLimit(1)
   }
   Spacer(minLength:0)
   HStack(spacing:12) {
    ForEach(Array(lights.enumerated()),id:\.offset) { _,l in
     HStack(spacing:5) {
      Circle().fill(l.1 == .off ? Color.clear : lightColor(l.1)).overlay(Circle().stroke(lightColor(l.1),lineWidth:1)).frame(width:7,height:7)
      Text(l.0).font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
     }
     .help(l.2)
    }
   }
  }
  .padding(.horizontal,26).padding(.top,14).padding(.bottom,8)
 }

 // MARK: Friday's slim contextual panel

 var fridayPanel: some View {
  let top = observations.first
  return VStack(spacing:0) {
   Button { withAnimation(reduceMotion ? nil : .easeInOut(duration:0.25)) { ui.fridayOpen.toggle() } } label: {
    HStack(spacing:10) {
     Circle().fill(RadialGradient(colors:[CoreStyle.crimson,CoreStyle.crimson.opacity(0.25)],center:.center,startRadius:1,endRadius:9)).frame(width:16,height:16)
      .shadow(color:CoreStyle.crimson.opacity(0.6),radius:4)
     Text("Friday").font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(CoreStyle.ink)
     Text(top?.text ?? "Nothing to point out right now.").font(.system(size:13,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.85)).lineLimit(1)
     Spacer(minLength:8)
     Text(ui.fridayOpen ? "less" : (observations.count > 1 ? "\(observations.count) notes" : "details")).font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.teal)
     Image(systemName:ui.fridayOpen ? "chevron.down" : "chevron.up").font(.system(size:10,weight:.semibold)).foregroundStyle(CoreStyle.teal)
    }
    .padding(.horizontal,26).padding(.vertical,10).contentShape(Rectangle())
   }
   .buttonStyle(.plain)
   if ui.fridayOpen {
    VStack(alignment:.leading,spacing:10) {
     if observations.isEmpty { Text("I have nothing to flag on this tab. Everything I can read here looks normal.").font(.system(size:13,design:.rounded)).foregroundStyle(CoreStyle.dim) }
     ForEach(observations.prefix(4)) { o in
      HStack(alignment:.top,spacing:10) {
       Circle().fill(tone(o.tone)).frame(width:8,height:8).padding(.top,5)
       VStack(alignment:.leading,spacing:2) {
        Text(o.text).font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.ink)
        Text(o.why).font(.system(size:12.5,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.7)).fixedSize(horizontal:false,vertical:true)
        Text(o.source).font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim)
       }
       Spacer(minLength:8)
       if let t = o.actionTitle, let run = o.run {
        Button(action:run) {
         Text(t).font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.teal)
          .padding(.horizontal,11).padding(.vertical,5).overlay(Capsule().stroke(CoreStyle.teal.opacity(0.6),lineWidth:1))
        }.buttonStyle(.plain)
       }
      }
     }
     Button { withAnimation(reduceMotion ? nil : .easeInOut(duration:0.25)) { ui.drawerOpen = true } } label: {
      Text("Ask Friday something ›").font(.system(size:12.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.teal)
     }.buttonStyle(.plain)
    }
    .padding(.horizontal,26).padding(.bottom,12)
    .transition(.move(edge:.bottom).combined(with:.opacity))
   }
  }
  .background(CoreStyle.charcoal.opacity(0.9))
  .overlay(alignment:.top) { Rectangle().fill(LinearGradient(colors:[.clear,CoreStyle.crimson.opacity(0.45),.clear],startPoint:.leading,endPoint:.trailing)).frame(height:1) }
 }

 // MARK: the collapsible drawer: the live tape and the command line

 var drawer: some View {
  VStack(spacing:0) {
   Button { withAnimation(reduceMotion ? nil : .easeInOut(duration:0.28)) { ui.drawerOpen.toggle() } } label: {
    HStack(spacing:10) {
     Image(systemName:ui.drawerOpen ? "chevron.down" : "chevron.up").font(.system(size:10,weight:.semibold)).foregroundStyle(CoreStyle.teal)
     Text("ACTIVITY & COMMAND LINE").font(.system(size:11,weight:.semibold,design:.rounded)).tracking(2).foregroundStyle(CoreStyle.dim)
     if !ui.drawerOpen {
      Text(newest).font(DeckMono.font(11)).foregroundStyle(CoreStyle.ink.opacity(0.7)).lineLimit(1)
     }
     Spacer(minLength:0)
     Text(ui.drawerOpen ? "hide" : "open").font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.teal)
    }
    .padding(.horizontal,26).padding(.vertical,10).contentShape(Rectangle())
   }
   .buttonStyle(.plain)
   if ui.drawerOpen {
    VStack(spacing:10) {
     tape.frame(height:150)
     terminal
    }
    .padding(.horizontal,22).padding(.bottom,12)
    .transition(.move(edge:.bottom).combined(with:.opacity))
   }
  }
  .background(CoreStyle.charcoal.opacity(0.96))
  .overlay(alignment:.top) { Rectangle().fill(CoreStyle.teal.opacity(0.18)).frame(height:1) }
 }
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
