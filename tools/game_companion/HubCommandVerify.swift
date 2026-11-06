import SwiftUI
import AppKit

// Command Core › Verification (LC-Pixels, 2026-11-06). The existing Real or Fake? engine (FakeCheck, via GuardHub) in Command Core's frame.
// HONEST by design: there is NO confidence percent, because nothing here measures one. The check reads only the words pasted (red flags: pressure,
// money talk, login asks, impersonation, odd links) on this Mac. It opens NO web page, so "Sources opened" says so plainly. The pasted text is never
// stored: Recent verifications keeps only the verdict and the red-flag count that Guard already logs.

struct CoreVerifyView: View {
 @ObservedObject var guardHub: GuardHub

 private func pill(_ text: String,_ color: Color = CoreStyle.teal,filled: Bool = false,_ action: @escaping () -> Void) -> some View {
  Button(action:action) {
   Text(text).font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(filled ? CoreStyle.bg : color)
    .padding(.horizontal,12).padding(.vertical,5)
    .background(Capsule().fill(filled ? color : Color.clear))
    .overlay(Capsule().stroke(color.opacity(0.7),lineWidth:1))
  }.buttonStyle(.plain)
 }

 private func ago(_ d: Date) -> String {
  let s = Int(Date().timeIntervalSince(d))
  return s < 90 ? "just now" : (s < 3600 ? "\(s / 60) min ago" : (s < 86400 ? "\(s / 3600) h ago" : "\(s / 86400) d ago"))
 }

 var empty: Bool { guardHub.fakeText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }

 func tint(_ r: FakeCheckReport) -> Color { r.flags.isEmpty ? CoreStyle.teal : (r.flags.count <= 2 ? CoreStyle.amber : CoreStyle.crimson) }

 var body: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:12) {
    inputCard
    HStack(alignment:.top,spacing:12) {
     VStack(spacing:12) {
      if let r = guardHub.fakeReport { resultCard(r) } else { emptyResult }
     }.frame(maxWidth:.infinity)
     VStack(spacing:12) {
      sourcesCard
      recentCard
     }.frame(width:290)
    }
    Text("A red-flag check can't prove something is real. When it matters, check it yourself through a site or number you already know.")
     .font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim)
   }
   .padding(.horizontal,24).padding(.bottom,16)
  }
  .scrollIndicators(.hidden)
 }

 var inputCard: some View {
  CoreCard(title:"What do you want to check?",icon:"checkmark.seal") {
   Text("Paste a message, email, alert, claim or link. It's read on this Mac only; nothing you paste leaves it.")
    .font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
   TextEditor(text:$guardHub.fakeText)
    .font(.system(size:13,design:.rounded)).foregroundStyle(CoreStyle.ink)
    .scrollContentBackground(.hidden)
    .padding(8).frame(height:96)
    .background(RoundedRectangle(cornerRadius:8).fill(Color.black.opacity(0.35)))
    .overlay(RoundedRectangle(cornerRadius:8).stroke(Color.white.opacity(0.08),lineWidth:1))
    .accessibilityLabel("Text or link to check")
   HStack(spacing:8) {
    pill("Analyze",CoreStyle.teal,filled:true) { guardHub.checkFake() }
     .keyboardShortcut(.return,modifiers:.command).opacity(empty ? 0.6 : 1).disabled(empty)
    pill("Clear",CoreStyle.dim) { guardHub.fakeText = "" }
    Spacer(minLength:0)
    Text("⌘↩ to analyze").font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
   }
  }
 }

 var emptyResult: some View {
  CoreCard(title:"Result",icon:"doc.text.magnifyingglass") {
   Text("Nothing checked yet. Paste something above and press Analyze.").font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.dim)
  }
 }

 func resultCard(_ r: FakeCheckReport) -> some View {
  let t = tint(r)
  return CoreCard(title:"Result",icon:"doc.text.magnifyingglass") {
   HStack(spacing:10) {
    Image(systemName:r.flags.isEmpty ? "checkmark.shield" : (r.flags.count <= 2 ? "exclamationmark.triangle" : "xmark.shield")).font(.system(size:22)).foregroundStyle(t)
    VStack(alignment:.leading,spacing:1) {
     Text(r.verdict).font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(CoreStyle.ink)
     Text("\(r.flags.count) red flag\(r.flags.count == 1 ? "" : "s") found in the words you pasted").font(.system(size:11,design:.rounded)).foregroundStyle(t)
    }
   }
   ForEach(Array(r.flags.enumerated()),id:\.offset) { e in
    HStack(alignment:.top,spacing:8) {
     Circle().fill(t).frame(width:5,height:5).padding(.top,6)
     Text(e.element).font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.88)).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
    }
   }
   if !r.advice.isEmpty {
    Text(r.advice).font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.ink)
     .padding(10).frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)
     .background(RoundedRectangle(cornerRadius:8).fill(t.opacity(0.10)))
   }
  }
 }

 // What was actually read. No page is opened, so this says exactly that, and lists the link names found in the text.
 var sourcesCard: some View {
  let links = FakeCheck.links(guardHub.fakeText)
  return CoreCard(title:"Sources opened",icon:"link") {
   Text("None. No website was opened or contacted; only the words you pasted were read.").font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.8)).fixedSize(horizontal:false,vertical:true)
   if links.isEmpty { Text("No links in the text.").font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim) }
   ForEach(Array(links.prefix(5).enumerated()),id:\.offset) { e in
    HStack(spacing:6) {
     Image(systemName:e.element.lowercased().hasPrefix("http://") ? "lock.open" : "lock").font(.system(size:10.5)).foregroundStyle(e.element.lowercased().hasPrefix("http://") ? CoreStyle.amber : CoreStyle.dim)
     Text(FakeCheck.host(e.element)).font(DeckMono.font(11)).foregroundStyle(CoreStyle.ink.opacity(0.85)).lineLimit(1)
    }
   }
   if links.count > 5 { Text("+ \(links.count - 5) more").font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim) }
  }
 }

 var recentCard: some View {
  let recent = guardHub.log.filter { $0.kind == "fakecheck" }.sorted { $0.at > $1.at }.prefix(5)
  return CoreCard(title:"Recent verifications",icon:"clock") {
   if recent.isEmpty { Text("None yet.").font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.dim) }
   ForEach(Array(recent)) { ev in
    VStack(alignment:.leading,spacing:1) {
     Text(ev.text.replacingOccurrences(of:"Real or Fake? ",with:"")).font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.85)).fixedSize(horizontal:false,vertical:true)
     Text(ago(ev.at)).font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
    }
   }
   Text("Only the verdict is kept, never your text.").font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
  }
 }
}

extension CompanionInterfaceView {
 var commandCoreVerify: some View {
  let g = GuardHub.shared
  var obs = coreObservations()
  if let r = g.fakeReport, !r.flags.isEmpty {
   obs.insert(CoreObservation(tone:r.flags.count <= 2 ? 2 : 3,text:"The last thing you checked: \(r.verdict.lowercased())",why:"\(r.flags.count) red flag\(r.flags.count == 1 ? "" : "s") in the words. Don't click or reply from the message.",source:"Real or Fake? red-flag check, this session"),at:0)
  }
  return coreFrame("Verification","Scam red-flag check of the words you paste. On this Mac; no pages opened.",observations:obs,
                   content:AnyView(CoreVerifyView(guardHub:g)))
 }
}
