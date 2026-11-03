import SwiftUI
import AppKit

// The Guard pages (2026-11-02): Guard, Real or Fake? and the Lab. Matthew: "a new interface, more security esque", "not in
// 'terminal' way ... a lot more modern". Midnight glass, cyan when things are fine, crimson when something needs him, SF Mono only
// for data. The engine is GuardHub (Guard.swift) and the rules are in GuardData.swift. Nothing here attacks or scans anything but
// his own Mac, and Unlock is a plain button only he presses (his choice: "itll only be me").

enum GuardStyle {
 static let cyan = Color(red:0.30,green:0.86,blue:0.96)
 static let crimson = Color(red:0.93,green:0.30,blue:0.40)
 static let amber = HubTheme.amber
 static let glassTop = Color(red:0.06,green:0.09,blue:0.17)
 static let glassBottom = Color(red:0.03,green:0.04,blue:0.09)
 static let mono = Font.system(size:12,weight:.medium,design:.monospaced)
 static func tint(_ verdict: GuardVerdict) -> Color {
  switch verdict {
  case .ok: return cyan
  case .warn: return crimson
  case .unknown: return amber
  }
 }
 static func word(_ verdict: GuardVerdict) -> String {
  switch verdict {
  case .ok: return "OK"
  case .warn: return "LOOK"
  case .unknown: return "UNSURE"
  }
 }
 static func icon(_ verdict: GuardVerdict) -> String {
  switch verdict {
  case .ok: return "checkmark.shield.fill"
  case .warn: return "exclamationmark.shield.fill"
  case .unknown: return "shield.lefthalf.filled"
  }
 }
}

// Page state lives in a small object, not @State: a command-line build can't expand SwiftUI's @State macro (only Xcode ships
// its plugin), the same reason Companion.swift holds the tab.
@MainActor final class GuardPageState: ObservableObject {
 @Published var forgetting: GuardKeyInfo?
 @Published var confirmUnlock = false
 @Published var pulse = false
 @Published var labDone = UserDefaults.standard.string(forKey:"guard.lab.done") ?? "" {
  didSet { UserDefaults.standard.set(labDone,forKey:"guard.lab.done") }
 }
}

struct GuardButtonStyle: ButtonStyle {
 var tint: Color
 @Environment(\.isEnabled) private var isEnabled
 func makeBody(configuration: Configuration) -> some View {
  configuration.label
   .font(.system(size:14,weight:.semibold))
   .foregroundStyle(Color.white)
   .padding(.horizontal,16)
   .frame(minHeight:44)
   .background(RoundedRectangle(cornerRadius:12,style:.continuous).fill(tint))
   .overlay(RoundedRectangle(cornerRadius:12,style:.continuous).stroke(Color.white.opacity(0.14),lineWidth:1))
   .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
   .scaleEffect(configuration.isPressed ? 0.97 : 1)
   .animation(.spring(response:0.28,dampingFraction:0.65),value:configuration.isPressed)
 }
}

extension View {
 // Midnight glass with a thin glowing edge in the card's accent colour.
 func guardCard(_ accent: Color = GuardStyle.cyan) -> some View {
  self.padding(20)
   .frame(maxWidth:.infinity,alignment:.leading)
   .background(LinearGradient(colors:[GuardStyle.glassTop.opacity(0.92),GuardStyle.glassBottom.opacity(0.92)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:20,style:.continuous))
   .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:20,style:.continuous))
   .overlay(RoundedRectangle(cornerRadius:20,style:.continuous).stroke(LinearGradient(colors:[accent.opacity(0.50),accent.opacity(0.06)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1))
 }
}

struct GuardTag: View {
 let text: String
 let tint: Color
 var body: some View {
  Text(text).font(.system(size:10,weight:.bold)).tracking(1.2)
   .foregroundStyle(tint)
   .padding(.horizontal,9).padding(.vertical,4)
   .background(Capsule().fill(tint.opacity(0.15)))
   .overlay(Capsule().stroke(tint.opacity(0.35),lineWidth:1))
 }
}

struct GuardHeading: View {
 let title: String
 let icon: String
 var tint: Color = GuardStyle.cyan
 var body: some View {
  HStack(spacing:10) {
   Image(systemName:icon).font(.system(size:15,weight:.semibold)).foregroundStyle(tint).frame(width:22)
   Text(title).font(.system(size:16,weight:.semibold)).foregroundStyle(HubTheme.text)
  }
  .accessibilityAddTraits(.isHeader)
 }
}

// MARK: Guard

struct GuardPage: View {
 @ObservedObject var guardHub = GuardHub.shared
 @StateObject private var ui = GuardPageState()

 var body: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:16) {
    shieldCard
    checksCard
    networkCard
    sweepCard
    keysCard
    kitCard
    logCard
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
  .alert("Unlock Friday?",isPresented:$ui.confirmUnlock) {
   Button("Unlock") { guardHub.unlock() }
   Button("Stay locked",role:.cancel) {}
  } message: {
   Text("Her hands, links, screen view, posts and stream controls come back, with the usual rules and the Allow box.")
  }
  .alert("Forget this key?",isPresented:Binding(get:{ ui.forgetting != nil },set:{ if !$0 { ui.forgetting = nil } })) {
   Button("Forget it",role:.destructive) {
    if let key = ui.forgetting { guardHub.forget(key) }
    ui.forgetting = nil
   }
   Button("Keep it",role:.cancel) { ui.forgetting = nil }
  } message: {
   Text(ui.forgetting.map { "The Helm deletes \($0.title) from this Mac. Whatever uses it stops until you paste a fresh one." } ?? "")
  }
 }

 var shieldCard: some View {
  let shield = guardHub.shield
  let tint = guardHub.locked ? GuardStyle.crimson : GuardStyle.tint(shield.verdict)
  return HStack(alignment:.center,spacing:26) {
   ZStack {
    Circle().stroke(tint.opacity(0.35),lineWidth:1.5).frame(width:140,height:140)
     .scaleEffect(ui.pulse ? 1.10 : 0.92).opacity(ui.pulse ? 0.15 : 0.9)
    Circle().stroke(tint.opacity(0.18),lineWidth:1).frame(width:112,height:112)
    Circle().fill(RadialGradient(colors:[tint.opacity(0.38),Color.clear],center:.center,startRadius:4,endRadius:72)).frame(width:140,height:140)
    Image(systemName:guardHub.locked ? "lock.shield.fill" : GuardStyle.icon(shield.verdict))
     .font(.system(size:60,weight:.semibold))
     .foregroundStyle(tint)
     .shadow(color:tint.opacity(0.65),radius:16)
   }
   .frame(width:150,height:150)
   .onAppear { withAnimation(.easeInOut(duration:2.4).repeatForever(autoreverses:true)) { ui.pulse = true } }
   .accessibilityHidden(true)

   VStack(alignment:.leading,spacing:10) {
    Text(guardHub.locked ? "LOCKDOWN" : "GUARD").font(.system(size:11,weight:.bold)).tracking(2.4).foregroundStyle(tint)
    Text(shield.line).font(.system(size:26,weight:.semibold)).foregroundStyle(HubTheme.text)
    Text(guardHub.lastChecked.map { "Last checked " + $0.formatted(date:.omitted,time:.shortened) } ?? "Not checked since The Helm opened.")
     .font(GuardStyle.mono).foregroundStyle(HubTheme.subtext)
    if guardHub.locked {
     Text("Friday can still talk, think, use her memory and music, and help with the checks. Her hands, screen view, links, posts and stream controls are off. Only you can unlock.")
      .font(.system(size:12.5)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
    }
    HStack(spacing:10) {
     if guardHub.locked {
      Button { ui.confirmUnlock = true } label: { Label("Unlock",systemImage:"lock.open.fill") }
       .buttonStyle(GuardButtonStyle(tint:GuardStyle.cyan.opacity(0.85)))
     } else {
      Button { guardHub.lock("Matthew pressed Lockdown") } label: { Label("Lockdown",systemImage:"lock.fill") }
       .buttonStyle(GuardButtonStyle(tint:GuardStyle.crimson))
       .help("Turns off Friday's hands, screen view, links, posts and stream controls until you press Unlock.")
     }
     Button { Task { await guardHub.runChecks() } } label: {
      Label(guardHub.checking ? "Checking…" : "Run checks",systemImage:"waveform.path.ecg")
     }
     .buttonStyle(GuardButtonStyle(tint:Color.white.opacity(0.12)))
     .disabled(guardHub.checking)
     if guardHub.checking { ProgressView().controlSize(.small) }
    }
    Toggle(isOn:Binding(get:{ guardHub.offline },set:{ guardHub.setOffline($0) })) {
     Text("Offline mode").font(.system(size:13.5,weight:.semibold)).foregroundStyle(HubTheme.text)
    }
    .toggleStyle(.switch)
    Text("Stops Friday's Google session, room reads and the Helper's Google brain. To cut the Mac off completely, also turn off Wi-Fi.")
     .font(.system(size:12)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
   }
   Spacer(minLength:0)
  }
  .guardCard(tint)
 }

 var checksCard: some View {
  VStack(alignment:.leading,spacing:12) {
   GuardHeading(title:"Mac health",icon:"desktopcomputer")
   if guardHub.results.isEmpty {
    Text("Press Run checks. Each check runs one of Apple's own read-only commands; nothing on your Mac is changed.")
     .font(.system(size:12.5)).foregroundStyle(HubTheme.subtext)
   }
   ForEach(guardHub.results,id:\.id) { result in
    HStack(alignment:.top,spacing:12) {
     Image(systemName:GuardStyle.icon(result.verdict)).font(.system(size:17)).foregroundStyle(GuardStyle.tint(result.verdict)).frame(width:22)
     VStack(alignment:.leading,spacing:4) {
      HStack(spacing:8) {
       Text(result.title).font(.system(size:13.5,weight:.semibold)).foregroundStyle(HubTheme.text)
       GuardTag(text:GuardStyle.word(result.verdict),tint:GuardStyle.tint(result.verdict))
      }
      Text(result.detail).font(GuardStyle.mono).foregroundStyle(HubTheme.subtext).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
      if !result.fix.isEmpty {
       Text(result.fix).font(.system(size:12.5)).foregroundStyle(HubTheme.text.opacity(0.85)).fixedSize(horizontal:false,vertical:true)
      }
     }
     Spacer(minLength:0)
    }
    .padding(.vertical,4)
   }
  }
  .guardCard()
 }

 var networkCard: some View {
  VStack(alignment:.leading,spacing:12) {
   HStack {
    GuardHeading(title:"Apps using the internet",icon:"antenna.radiowaves.left.and.right")
    Spacer()
    if !guardHub.network.isEmpty { Text("\(guardHub.network.count) apps").font(GuardStyle.mono).foregroundStyle(HubTheme.subtext) }
   }
   if guardHub.network.isEmpty {
    Text("Run checks to see which of your apps are talking to the internet right now. New ones are marked.")
     .font(.system(size:12.5)).foregroundStyle(HubTheme.subtext)
   }
   ForEach(guardHub.network,id:\.name) { app in
    HStack(spacing:10) {
     Circle().fill(app.isNew ? GuardStyle.crimson : GuardStyle.cyan.opacity(0.7)).frame(width:7,height:7)
     Text(app.name).font(GuardStyle.mono).foregroundStyle(HubTheme.text).textSelection(.enabled)
     if app.isNew { GuardTag(text:"NEW",tint:GuardStyle.crimson) }
     Spacer()
     Text("\(app.connections) link\(app.connections == 1 ? "" : "s")").font(GuardStyle.mono).foregroundStyle(HubTheme.subtext)
    }
    .frame(minHeight:26)
   }
   if guardHub.network.contains(where: { $0.isNew }) {
    Text("New isn't the same as bad: an app you just installed or opened shows up here too. If you don't know a name, ask Claude before you delete anything.")
     .font(.system(size:12)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
   }
  }
  .guardCard()
 }

 var sweepCard: some View {
  VStack(alignment:.leading,spacing:12) {
   GuardHeading(title:"Account sweep",icon:"person.badge.shield.checkmark.fill")
   Text("Leaks show up on these pages first. You press Open, not Friday, so they work in lockdown too; they open in your own browser. Once a month is a good habit.")
    .font(.system(size:12.5)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
   ForEach(GuardSweep.items,id:\.url) { item in
    HStack(alignment:.center,spacing:12) {
     VStack(alignment:.leading,spacing:3) {
      Text(item.title).font(.system(size:13.5,weight:.semibold)).foregroundStyle(HubTheme.text)
      Text(item.why).font(.system(size:12)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
     }
     Spacer(minLength:8)
     Button { if let url = URL(string:item.url) { NSWorkspace.shared.open(url) } } label: { Label("Open",systemImage:"arrow.up.right") }
      .buttonStyle(GuardButtonStyle(tint:Color.white.opacity(0.10)))
      .help(item.url)
    }
   }
  }
  .guardCard()
 }

 var keysCard: some View {
  VStack(alignment:.leading,spacing:12) {
   GuardHeading(title:"Keys on this Mac",icon:"key.fill")
   Text("If you think a key leaked: Forget it here, then delete it on its site too, and make a fresh one. The Helm never shows a key's value.")
    .font(.system(size:12.5)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
   ForEach(GuardKeys.all,id:\.service) { key in
    let saved = guardHub.isSaved(key)
    HStack(spacing:12) {
     Text(key.title).font(.system(size:13.5,weight:.medium)).foregroundStyle(HubTheme.text)
     GuardTag(text:saved ? "SAVED" : "NOT SAVED",tint:saved ? GuardStyle.cyan : HubTheme.subtext)
     Spacer(minLength:8)
     Button { if let url = URL(string:key.renew) { NSWorkspace.shared.open(url) } } label: { Text("Its site") }
      .buttonStyle(GuardButtonStyle(tint:Color.white.opacity(0.10)))
     if saved {
      Button { ui.forgetting = key } label: { Label("Forget",systemImage:"trash") }
       .buttonStyle(GuardButtonStyle(tint:GuardStyle.crimson.opacity(0.55)))
     }
    }
   }
  }
  .guardCard()
 }

 var kitCard: some View {
  VStack(alignment:.leading,spacing:12) {
   GuardHeading(title:"If the internet goes bad",icon:"exclamationmark.triangle.fill",tint:GuardStyle.amber)
   ForEach(Array(GuardKit.steps.enumerated()),id:\.offset) { entry in
    HStack(alignment:.top,spacing:12) {
     Text("\(entry.offset + 1)").font(.system(size:12,weight:.bold,design:.monospaced)).foregroundStyle(GuardStyle.amber)
      .frame(width:24,height:24).background(Circle().fill(GuardStyle.amber.opacity(0.14)))
     Text(entry.element).font(.system(size:13)).foregroundStyle(HubTheme.text.opacity(0.9)).fixedSize(horizontal:false,vertical:true)
    }
   }
   HStack(alignment:.top,spacing:10) {
    Image(systemName:"person.2.wave.2.fill").foregroundStyle(GuardStyle.cyan)
    Text(GuardKit.codeWord).font(.system(size:12.5)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
   }
   .padding(.top,4)
  }
  .guardCard(GuardStyle.amber)
 }

 var logCard: some View {
  VStack(alignment:.leading,spacing:10) {
   HStack {
    GuardHeading(title:"Alert log",icon:"list.bullet.rectangle.portrait.fill")
    Spacer()
    if !guardHub.log.isEmpty {
     Button { guardHub.clearLog() } label: { Text("Clear") }.buttonStyle(GuardButtonStyle(tint:Color.white.opacity(0.10)))
    }
   }
   if guardHub.log.isEmpty {
    Text("Nothing yet. Lockdowns, checks, warnings and forgotten keys are written here, on this Mac only.")
     .font(.system(size:12.5)).foregroundStyle(HubTheme.subtext)
   }
   ForEach(Array(guardHub.log.reversed().prefix(60))) { event in
    HStack(alignment:.firstTextBaseline,spacing:10) {
     Text(event.at.formatted(.dateTime.month(.abbreviated).day().hour().minute())).font(GuardStyle.mono).foregroundStyle(HubTheme.subtext).frame(width:118,alignment:.leading)
     GuardTag(text:event.kind.uppercased(),tint:["lockdown","warning"].contains(event.kind) ? GuardStyle.crimson : GuardStyle.cyan)
     Text(event.text).font(.system(size:12.5)).foregroundStyle(HubTheme.text.opacity(0.9)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
     Spacer(minLength:0)
    }
   }
  }
  .guardCard()
 }
}

// MARK: Real or Fake?

struct GuardFakePage: View {
 @ObservedObject var guardHub = GuardHub.shared

 var body: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:16) {
    VStack(alignment:.leading,spacing:12) {
     GuardHeading(title:"Real or Fake?",icon:"checkmark.seal.fill")
     Text("Paste a text, email or alert. Friday looks for the red flags scams and fake alerts use. It's checked on this Mac only; nothing you paste leaves it.")
      .font(.system(size:12.5)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
     TextEditor(text:$guardHub.fakeText)
      .font(.system(size:13.5))
      .scrollContentBackground(.hidden)
      .padding(10)
      .frame(minHeight:160)
      .background(Color.black.opacity(0.35),in:RoundedRectangle(cornerRadius:12,style:.continuous))
      .overlay(RoundedRectangle(cornerRadius:12,style:.continuous).stroke(GuardStyle.cyan.opacity(0.25),lineWidth:1))
     HStack(spacing:10) {
      Button { guardHub.checkFake() } label: { Label("Check it",systemImage:"magnifyingglass") }
       .buttonStyle(GuardButtonStyle(tint:GuardStyle.cyan.opacity(0.80)))
       .disabled(guardHub.fakeText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
       .keyboardShortcut(.return,modifiers:.command)
      Button { guardHub.fakeText = "" } label: { Text("Clear") }
       .buttonStyle(GuardButtonStyle(tint:Color.white.opacity(0.10)))
     }
    }
    .guardCard()

    if let report = guardHub.fakeReport { reportCard(report) }

    Text("A red-flag check can't prove something is real. When it matters, check it yourself through a site or number you already know.")
     .font(.system(size:11.5)).foregroundStyle(HubTheme.subtext)
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
 }

 func reportCard(_ report: FakeCheckReport) -> some View {
  let tint = report.flags.isEmpty ? GuardStyle.cyan : (report.flags.count <= 2 ? GuardStyle.amber : GuardStyle.crimson)
  return VStack(alignment:.leading,spacing:12) {
   HStack(spacing:14) {
    Image(systemName:report.flags.isEmpty ? "checkmark.shield.fill" : (report.flags.count <= 2 ? "exclamationmark.triangle.fill" : "xmark.shield.fill"))
     .font(.system(size:34,weight:.semibold)).foregroundStyle(tint).shadow(color:tint.opacity(0.5),radius:10)
    VStack(alignment:.leading,spacing:3) {
     Text(report.verdict).font(.system(size:24,weight:.semibold)).foregroundStyle(HubTheme.text)
     Text("\(report.flags.count) red flag\(report.flags.count == 1 ? "" : "s")").font(GuardStyle.mono).foregroundStyle(tint)
    }
   }
   ForEach(Array(report.flags.enumerated()),id:\.offset) { entry in
    HStack(alignment:.top,spacing:10) {
     Image(systemName:"flag.fill").font(.system(size:12)).foregroundStyle(tint).padding(.top,2)
     Text(entry.element).font(.system(size:13)).foregroundStyle(HubTheme.text.opacity(0.9)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
    }
   }
   if !report.advice.isEmpty {
    Text(report.advice).font(.system(size:13,weight:.medium)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
     .padding(12).frame(maxWidth:.infinity,alignment:.leading)
     .background(tint.opacity(0.10),in:RoundedRectangle(cornerRadius:12,style:.continuous))
   }
  }
  .guardCard(tint)
 }
}

// MARK: Lab

struct GuardLabPage: View {
 @StateObject private var ui = GuardPageState()

 var body: some View {
  let ticked = GuardLab.done(ui.labDone)
  let ids = GuardLab.lessons.map { $0.id } + GuardLab.practice.map { $0.id }
  let count = ids.filter { ticked.contains($0) }.count
  return ScrollView {
   VStack(alignment:.leading,spacing:16) {
    VStack(alignment:.leading,spacing:12) {
     HStack {
      GuardHeading(title:"Lab: learn to defend",icon:"flask.fill")
      Spacer()
      Text("\(count) of \(ids.count) done").font(GuardStyle.mono).foregroundStyle(GuardStyle.cyan)
     }
     ProgressView(value:Double(count),total:Double(max(ids.count,1))).tint(GuardStyle.cyan)
     HStack(alignment:.top,spacing:10) {
      Image(systemName:"hand.raised.fill").foregroundStyle(GuardStyle.crimson)
      Text(GuardLab.rule).font(.system(size:13,weight:.medium)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
     }
     .padding(12).frame(maxWidth:.infinity,alignment:.leading)
     .background(GuardStyle.crimson.opacity(0.10),in:RoundedRectangle(cornerRadius:12,style:.continuous))
    }
    .guardCard()

    LazyVGrid(columns:[GridItem(.adaptive(minimum:300),spacing:14)],alignment:.leading,spacing:14) {
     ForEach(GuardLab.lessons,id:\.id) { lesson in lessonCard(lesson,done:ticked.contains(lesson.id)) }
    }

    VStack(alignment:.leading,spacing:12) {
     GuardHeading(title:"Practice (free, built to be practised on)",icon:"target")
     ForEach(GuardLab.practice,id:\.id) { site in
      HStack(spacing:12) {
       tick(site.id,done:ticked.contains(site.id))
       VStack(alignment:.leading,spacing:3) {
        Text(site.title).font(.system(size:13.5,weight:.semibold)).foregroundStyle(HubTheme.text)
        Text(site.why).font(.system(size:12)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
       }
       Spacer(minLength:8)
       Button { if let url = URL(string:site.url) { NSWorkspace.shared.open(url) } } label: { Label("Open",systemImage:"arrow.up.right") }
        .buttonStyle(GuardButtonStyle(tint:Color.white.opacity(0.10)))
        .help(site.url)
      }
     }
    }
    .guardCard()

    Text("Next on the list: a code scratchpad for Python, right on this page.").font(.system(size:11.5)).foregroundStyle(HubTheme.subtext)
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
 }

 func tick(_ id: String,done isDone: Bool) -> some View {
  Button { ui.labDone = GuardLab.toggled(id,in:ui.labDone) } label: {
   Image(systemName:isDone ? "checkmark.circle.fill" : "circle").font(.system(size:22)).foregroundStyle(isDone ? GuardStyle.cyan : HubTheme.subtext)
    .frame(width:44,height:44)
  }
  .buttonStyle(.plain)
  .accessibilityLabel(isDone ? "Done. Press to undo." : "Mark done")
 }

 func lessonCard(_ lesson: GuardLesson,done isDone: Bool) -> some View {
  VStack(alignment:.leading,spacing:10) {
   HStack(spacing:10) {
    Image(systemName:lesson.icon).font(.system(size:18,weight:.semibold)).foregroundStyle(GuardStyle.cyan)
     .frame(width:36,height:36).background(Circle().fill(GuardStyle.cyan.opacity(0.12)))
    Text(lesson.title).font(.system(size:14.5,weight:.semibold)).foregroundStyle(HubTheme.text)
    Spacer(minLength:0)
    tick(lesson.id,done:isDone)
   }
   Text(lesson.body).font(.system(size:12.5)).foregroundStyle(HubTheme.text.opacity(0.85)).fixedSize(horizontal:false,vertical:true)
   HStack(alignment:.top,spacing:8) {
    Text("TRY IT").font(.system(size:10,weight:.bold)).tracking(1.2).foregroundStyle(GuardStyle.cyan).padding(.top,2)
    Text(lesson.tryIt).font(.system(size:12)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
   }
  }
  .guardCard(isDone ? GuardStyle.cyan : Color.white)
  .frame(maxHeight:.infinity,alignment:.top)
 }
}

// The three pages as hub sections.
extension CompanionInterfaceView {
 var hubGuard: some View { GuardPage() }
 var hubRealOrFake: some View { GuardFakePage() }
 var hubLab: some View { GuardLabPage() }
}
