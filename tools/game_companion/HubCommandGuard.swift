import SwiftUI
import AppKit

// Command Core › Guard (Friday, 2026-11-06). Defensive only, like the Guard it sits on: Mac health checks, apps online, Lockdown, Offline mode, the
// alert log. The reference mockup showed "SECURE", blocked threats and a malware scan; THIS tab never says those unless something measured them.
// What it can honestly say: how many of Guard's own read-only checks came back ok, which need a look (with the fix in plain words), which apps are
// using the internet, and what Guard logged. Every number carries the time of the check. Account sweep, keys and the bad-day kit stay one tap away.

@MainActor final class CoreGuardUI: ObservableObject {
 static let shared = CoreGuardUI()
 @Published var classic = false
 @Published var openCheck: String?
}

struct CoreGuardView: View {
 @ObservedObject var guardHub: GuardHub
 @ObservedObject var ui = CoreGuardUI.shared
 var classic: AnyView

 private func card<C: View>(_ title: String,@ViewBuilder _ content: () -> C) -> some View {
  CoreCard(title:coreTitle(title)) { content() }
 }

 private func pill(_ text: String,_ color: Color = CoreStyle.teal,_ action: @escaping () -> Void) -> some View {
  Button(action:action) {
   Text(text).font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(color)
    .padding(.horizontal,11).padding(.vertical,5).overlay(Capsule().stroke(color.opacity(0.6),lineWidth:1))
  }.buttonStyle(.plain)
 }

 private func ago(_ d: Date) -> String {
  let s = Int(Date().timeIntervalSince(d))
  return s < 90 ? "just now" : (s < 3600 ? "\(s / 60) min ago" : (s < 86400 ? "\(s / 3600) h ago" : "\(s / 86400) d ago"))
 }

 var counts: (ok: Int,warn: Int,unknown: Int) { CoreFacts.summarize(guardHub.results) }

 // The shield: one honest state.
 var shieldState: (word: String,line: String,color: Color,icon: String) {
  let c = counts
  let when = guardHub.lastChecked.map { "Guard checked \(ago($0))" } ?? "not checked yet"
  if guardHub.locked { return ("LOCKDOWN","Her hands, screen view and posts are off.",CoreStyle.amber,"lock.fill") }
  if guardHub.results.isEmpty { return ("NOT CHECKED","Press Run checks.",CoreStyle.dim,"shield") }
  if c.warn > 0 { return ("\(c.warn) TO LOOK AT","\(c.ok) of \(guardHub.results.count) checks ok · \(when)",CoreStyle.amber,"exclamationmark.shield.fill") }
  if c.unknown > 0 { return ("\(c.ok) OK · \(c.unknown) UNREAD","\(c.unknown) check\(c.unknown == 1 ? "" : "s") couldn't be read · \(when)",CoreStyle.teal,"shield.lefthalf.filled") }
  return ("ALL CHECKS OK","\(c.ok) of \(guardHub.results.count) checks ok · \(when)",CoreStyle.emerald,"checkmark.shield.fill")
 }

 var body: some View {
  if ui.classic {
   VStack(spacing:0) {
    HStack { pill("‹ Back to Guard") { ui.classic = false }; Spacer() }.padding(.horizontal,26).padding(.vertical,8)
    classic
   }
  } else {
   ScrollView {
    VStack(alignment:.leading,spacing:12) {
     HStack(alignment:.top,spacing:14) {
      shieldCard.frame(width:250)
      checksCard
      eventsCard.frame(width:250)
     }
     statTiles
     recommended
    }
    .padding(.horizontal,22).padding(.vertical,4)
   }
  }
 }

 var shieldCard: some View {
  let s = shieldState
  return card("PROTECTION STATUS") {
   VStack(spacing:10) {
    ZStack {
     Circle().stroke(s.color.opacity(0.35),lineWidth:3)
     Circle().stroke(CoreStyle.crimson.opacity(0.25),lineWidth:1).padding(-8)
     Image(systemName:s.icon).font(.system(size:38,weight:.light)).foregroundStyle(s.color)
    }
    .frame(width:104,height:104)
    Text(s.word).font(.system(size:14,weight:.semibold,design:.rounded)).tracking(1.5).foregroundStyle(s.color)
    Text(s.line).font(.system(size:12.5,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.8)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
    HStack(spacing:8) {
     pill(guardHub.checking ? "checking…" : "Run checks") { Task { await guardHub.runChecks() } }.disabled(guardHub.checking || guardHub.locked)
    }
   }
   .frame(maxWidth:.infinity)
  }
 }

 var checksCard: some View {
  card("MAC CHECKS · GUARD'S OWN, READ-ONLY") {
   if guardHub.results.isEmpty {
    Text(guardHub.locked ? "Checks are paused while Lockdown is on." : "Nothing read yet. Press Run checks.").font(.system(size:13,design:.rounded)).foregroundStyle(CoreStyle.dim)
   }
   ForEach(Array(guardHub.results.enumerated()),id:\.offset) { _,r in
    let open = ui.openCheck == r.id
    VStack(alignment:.leading,spacing:4) {
     Button { ui.openCheck = open ? nil : r.id } label: {
      HStack(spacing:9) {
       Image(systemName:r.verdict == .ok ? "checkmark.circle.fill" : (r.verdict == .warn ? "exclamationmark.circle.fill" : "questionmark.circle")).foregroundStyle(r.verdict == .ok ? CoreStyle.emerald : (r.verdict == .warn ? CoreStyle.amber : CoreStyle.dim))
       Text(r.title).font(.system(size:13.5,design:.rounded)).foregroundStyle(CoreStyle.ink).lineLimit(1)
       Spacer(minLength:6)
       Text(r.verdict == .ok ? "ok" : (r.verdict == .warn ? "needs a look" : "unknown")).font(.system(size:12.5,design:.rounded)).foregroundStyle(r.verdict == .ok ? CoreStyle.emerald : (r.verdict == .warn ? CoreStyle.amber : CoreStyle.dim))
       Image(systemName:open ? "chevron.down" : "chevron.right").font(.system(size:10)).foregroundStyle(CoreStyle.dim)
      }
      .contentShape(Rectangle())
     }.buttonStyle(.plain)
     if open {
      Text(r.detail).font(.system(size:12.5,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.75)).fixedSize(horizontal:false,vertical:true).padding(.leading,26)
      if r.verdict != .ok, !r.fix.isEmpty { Text("What to do: " + r.fix).font(.system(size:12.5,design:.rounded)).foregroundStyle(CoreStyle.amber).fixedSize(horizontal:false,vertical:true).padding(.leading,26) }
     }
    }
    Divider().overlay(Color.white.opacity(0.05))
   }
  }
 }

 var eventsCard: some View {
  card("RECENT EVENTS · GUARD'S LOG") {
   let events = Array(guardHub.log.suffix(7).reversed())
   if events.isEmpty { Text("Guard hasn't logged anything yet.").font(.system(size:13,design:.rounded)).foregroundStyle(CoreStyle.dim) }
   ForEach(events) { e in
    VStack(alignment:.leading,spacing:1) {
     Text(e.text).font(.system(size:12.5,design:.rounded)).foregroundStyle(CoreStyle.ink).lineLimit(3).fixedSize(horizontal:false,vertical:true)
     Text(ago(e.at)).font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim)
    }
   }
  }
 }

 var statTiles: some View {
  let c = counts
  let fresh = guardHub.network.filter { $0.isNew }.count
  let when = guardHub.lastChecked.map { "as of \(ago($0))" } ?? "not checked"
  return HStack(spacing:12) {
   stat("Checks ok","\(guardHub.results.isEmpty ? "–" : "\(c.ok)")",CoreStyle.emerald,when)
   stat("Need a look","\(guardHub.results.isEmpty ? "–" : "\(c.warn)")",c.warn > 0 ? CoreStyle.amber : CoreStyle.ink,when)
   stat("Apps online",guardHub.network.isEmpty ? "–" : "\(guardHub.network.count)",CoreStyle.teal,when)
   stat("New apps",guardHub.network.isEmpty ? "–" : "\(fresh)",fresh > 0 ? CoreStyle.amber : CoreStyle.ink,"since Guard's first look")
  }
 }

 func stat(_ title: String,_ value: String,_ color: Color,_ foot: String) -> some View {
  VStack(spacing:3) {
   Text(title).font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.dim)
   Text(value).font(.system(size:24,weight:.light,design:.rounded)).foregroundStyle(color)
   Text(foot).font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
  }
  .frame(maxWidth:.infinity).padding(.vertical,12)
  .background(RoundedRectangle(cornerRadius:11).fill(HubTheme.hex(0x111114)))
  .overlay(RoundedRectangle(cornerRadius:11).stroke(Color.white.opacity(0.065),lineWidth:1))
 }

 var recommended: some View {
  card("CONTROLS & NEXT STEPS") {
   HStack(spacing:10) {
    if guardHub.locked {
     pill("Unlock",CoreStyle.emerald) { guardHub.unlock() }
    } else {
     pill("Lockdown",CoreStyle.crimson) { guardHub.lock("Matthew pressed Lockdown in Command Core") }
    }
    pill(guardHub.offline ? "Offline mode: ON (turn off)" : "Offline mode") { guardHub.setOffline(!guardHub.offline) }
    pill("Account sweep, keys and bad-day kit ›") { ui.classic = true }
    Spacer(minLength:0)
   }
   let warns = guardHub.results.filter { $0.verdict == .warn }
   if warns.isEmpty {
    Text(guardHub.results.isEmpty ? "Run the checks and I'll list anything to fix here." : "No fixes needed right now.").font(.system(size:12.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
   }
   ForEach(Array(warns.enumerated()),id:\.offset) { _,r in
    Text("• \(r.title): \(r.fix.isEmpty ? r.detail : r.fix)").font(.system(size:12.5,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.85)).fixedSize(horizontal:false,vertical:true)
   }
  }
 }
}

extension CompanionInterfaceView {
 var commandCoreGuard: some View {
  let g = GuardHub.shared
  let c = CoreFacts.summarize(g.results)
  let sub = g.locked ? "Lockdown is on" : (g.results.isEmpty ? "Not checked yet" : (c.warn > 0 ? "\(c.warn) check\(c.warn == 1 ? "" : "s") need a look" : (c.unknown > 0 ? "\(c.ok) ok · \(c.unknown) couldn't be read" : "All of Guard's checks are ok")) + (g.lastChecked.map { " · checked \(coreAgo($0))" } ?? ""))
  return coreFrame("Guard",sub,tone:c.warn > 0 || g.locked ? 2 : 0,observations:coreObservations(),
                   content:AnyView(CoreGuardView(guardHub:g,classic:AnyView(hubGuard))))
 }
}
