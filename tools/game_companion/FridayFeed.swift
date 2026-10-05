import SwiftUI
import AppKit

// The Feed page: what Matthew and Friday said to each other, newest at the bottom, plus the things she did for him.
// It lives on this Mac only (Application Support/GameCompanion/FridayFeed.json), never in Git. Turn "Remember" off and nothing is
// written to disk (the file is deleted too); the feed then lasts only until the app closes. Friday does not read it back; it is a
// record for Matthew, and Copy puts it on the clipboard so he can paste it into a chat with Claude or GPT when he wants them to see it.
@MainActor final class FridayFeed: ObservableObject {
 @Published var entries: [FeedEntry] = []
 @Published var remember = UserDefaults.standard.object(forKey:"feed.remember") as? Bool ?? true {
  didSet {
   UserDefaults.standard.set(remember,forKey:"feed.remember")
   if remember { persist() } else { try? FileManager.default.removeItem(at:fileURL) }
  }
 }
 @Published var confirmClear = false
 @Published var copied = ""
 let fileURL: URL

 init() {
  fileURL = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("GameCompanion/FridayFeed.json")
  if remember { load() }
 }

 func add(_ who: String,_ text: String) {
  entries = FeedFormat.appending(entries,who:who,text:text)
  persist()
 }

 func clear() {
  entries = []
  try? FileManager.default.removeItem(at:fileURL)
 }

 func copy(last count: Int?) {
  let text = FeedFormat.transcript(entries,last:count)
  guard !text.isEmpty else { copied = "Nothing to copy yet"; return }
  let pasteboard = NSPasteboard.general
  pasteboard.clearContents()
  pasteboard.setString(text,forType:.string)
  copied = count == nil ? "Copied everything" : "Copied the last \(min(count ?? 0,entries.count))"
  Task {
   try? await Task.sleep(nanoseconds:2_500_000_000)
   copied = ""
  }
 }

 private func load() {
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .iso8601
  guard let data = try? Data(contentsOf:fileURL), let saved = try? decoder.decode([FeedEntry].self,from:data) else { return }
  entries = Array(saved.suffix(FeedFormat.keepEntries))
 }

 private func persist() {
  guard remember else { return }
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  guard let data = try? encoder.encode(entries) else { return }
  try? FileManager.default.createDirectory(at:fileURL.deletingLastPathComponent(),withIntermediateDirectories:true)
  try? data.write(to:fileURL,options:.atomic)
 }
}

extension CompanionInterfaceView {
 var hubFeed: some View {
  VStack(spacing:0) {
   hubFeedHeader.padding(.horizontal,32).padding(.bottom,12)
   if feed.entries.isEmpty {
    VStack(spacing:8) {
     Image(systemName:"text.bubble").font(.system(size:34)).foregroundStyle(Color.white.opacity(0.3))
     Text("Nothing here yet").font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
     Text("Start Friday and talk to her. What you both say, and what she does for you, lands here.").font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(0.55)).multilineTextAlignment(.center)
    }
    .frame(maxWidth:.infinity,maxHeight:.infinity).padding(40)
   } else {
    ScrollViewReader { proxy in
     ScrollView {
      LazyVStack(spacing:10) {
       ForEach(Array(feed.entries.enumerated()),id:\.element.id) { index,entry in
        hubFeedRow(entry,previous:index > 0 ? feed.entries[index - 1] : nil)
       }
      }
      .padding(.horizontal,32).padding(.vertical,6)
     }
     .scrollIndicators(.hidden)
     .onAppear { if let last = feed.entries.last { proxy.scrollTo(last.id,anchor:.bottom) } }
     .onChange(of:feed.entries.count) { _,_ in
      if let last = feed.entries.last { withAnimation(.easeOut(duration:0.25)) { proxy.scrollTo(last.id,anchor:.bottom) } }
     }
    }
   }
   Text("Saved on this Mac only, never on GitHub. Google still hears the audio while Friday is live, as always. Friday doesn't read this feed back; it's your record. Press Copy to paste it to Claude or GPT.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.4)).padding(.horizontal,32).padding(.vertical,12)
  }
  .confirmationDialog("Clear the whole feed?",isPresented:$feed.confirmClear) {
   Button("Clear it",role:.destructive) { feed.clear() }
  } message: { Text("This deletes the saved copy on this Mac. It can't be undone.") }
 }

 var hubFeedHeader: some View {
  HStack(spacing:10) {
   hubPill("ON THIS MAC ONLY",tint:HubColor.sky)
   Text("\(feed.entries.count) message\(feed.entries.count == 1 ? "" : "s")").font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
   if !feed.copied.isEmpty { Text(feed.copied).font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(HubColor.green) }
   Spacer()
   Toggle("Remember between sessions",isOn:$feed.remember).toggleStyle(.switch).font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.7))
   Button { feed.copy(last:20) } label: { Label("Copy last 20",systemImage:"doc.on.doc") }
    .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   Button { feed.copy(last:nil) } label: { Label("Copy all",systemImage:"doc.on.doc.fill") }
    .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   Button { feed.confirmClear = true } label: { Label("Clear",systemImage:"trash") }
    .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    .disabled(feed.entries.isEmpty)
  }
 }

 @ViewBuilder func hubFeedRow(_ entry: FeedEntry,previous: FeedEntry?) -> some View {
  if previous == nil || !Calendar.current.isDate(previous?.date ?? entry.date,inSameDayAs:entry.date) {
   Text(entry.date.formatted(date:.complete,time:.omitted)).font(.system(size:11,weight:.semibold,design:.rounded)).tracking(0.6).foregroundStyle(Color.white.opacity(0.4)).padding(.top,10)
  }
  switch entry.who {
  case "you":
   HStack {
    Spacer(minLength:80)
    VStack(alignment:.trailing,spacing:3) {
     Text(entry.text).font(.system(size:14,design:.rounded)).foregroundStyle(Color.white).textSelection(.enabled)
      .padding(.horizontal,14).padding(.vertical,10)
      .background(RoundedRectangle(cornerRadius:18,style:.continuous).fill(LinearGradient(colors:[Noir.crimsonLight.opacity(0.9),Noir.crimson],startPoint:.topLeading,endPoint:.bottomTrailing)))
     Text(entry.date,style:.time).font(.system(size:10.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.35))
    }
   }
  case "friday":
   HStack {
    VStack(alignment:.leading,spacing:3) {
     Text(entry.text).font(.system(size:14,design:.rounded)).foregroundStyle(Color.white.opacity(0.95)).textSelection(.enabled)
      .padding(.horizontal,14).padding(.vertical,10)
      .hubCard(radius:18)
     Text("Friday · \(entry.date.formatted(date:.omitted,time:.shortened))").font(.system(size:10.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.35))
    }
    Spacer(minLength:80)
   }
  default:
   HStack(spacing:8) {
    Image(systemName:"bolt.fill").font(.system(size:10)).foregroundStyle(HubColor.violet)
    Text(entry.text).font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.75)).textSelection(.enabled)
   }
   .padding(.horizontal,12).padding(.vertical,7)
   .background(Capsule().fill(HubColor.violet.opacity(0.16)))
   .frame(maxWidth:.infinity)
  }
 }
}
