import SwiftUI
import Foundation

// The usage ledger (NB2, 2026-11-06; idea from the StarNet study, Matthew's GO via Roxy for a side branch only).
// One line per Claude engine run the app starts: Friday's brain, Switchboard jobs, relays and wakes.
// HONEST BY DESIGN:
//  - Only what was measured: who, when, how long (our own clock), whether it worked, and the token counts the engine itself
//    reported in its final "result" object. If the engine didn't report a number, it is stored as nil and shown as "not reported",
//    never as 0, and counted apart.
//  - No prices. The engine prints a dollar figure, but on a Max plan that is an API-price equivalent, not a bill, so it is not stored.
//  - No message text. The ledger never holds a prompt, an answer or a name of anything Matthew said: only labels like "Friday (brain)".
//  - Local only, per app ID (test copies never write the real Helm's ledger), last 500 runs. No network, no polling.

struct UsageEntry: Codable, Identifiable, Equatable {
 var id: String
 var at: Date               // when the run started
 var who: String            // "Friday (brain)", "Switchboard job", "Relay to LC-Manager", "Wake: LC-Pixels"
 var job: String            // "#12", "question", a chat name: a label, never message text
 var seconds: Double        // measured by The Helm (start to end)
 var ok: Bool               // PROVEN success: a relay/wake only when delivery was proven, a job/answer only when the engine said ok
 var model: String?         // from the engine's modelUsage keys; nil = not reported
 var inputTokens: Int?      // usage.input_tokens
 var outputTokens: Int?     // usage.output_tokens
 var cacheReadTokens: Int?  // usage.cache_read_input_tokens
 var cacheWriteTokens: Int? // usage.cache_creation_input_tokens

 var reported: Bool { inputTokens != nil || outputTokens != nil }
 // Everything the model read for this run, cached parts included. nil when nothing was reported.
 var tokensIn: Int? {
  guard inputTokens != nil || cacheReadTokens != nil || cacheWriteTokens != nil else { return nil }
  return (inputTokens ?? 0) + (cacheReadTokens ?? 0) + (cacheWriteTokens ?? 0)
 }
}

enum UsageLedgerRules {
 static let keep = 500

 struct Reported: Equatable { var model: String?; var input: Int?; var output: Int?; var cacheRead: Int?; var cacheWrite: Int? }

 // The engine's last {"type":"result", ...} object, for both --output-format json (one object) and stream-json (many lines).
 static func reported(from data: Data) -> Reported {
  let lines = String(decoding:data,as:UTF8.self).split(whereSeparator:\.isNewline).reversed()
  for line in lines {
   guard let j = (try? JSONSerialization.jsonObject(with:Data(line.utf8))) as? [String:Any], (j["type"] as? String) == "result" else { continue }
   let u = j["usage"] as? [String:Any]
   func n(_ k: String) -> Int? { (u?[k] as? NSNumber)?.intValue }
   let models = (j["modelUsage"] as? [String:Any])?.keys.sorted()
   return Reported(model:(models?.isEmpty ?? true) ? nil : models!.joined(separator:", "),
                   input:n("input_tokens"),output:n("output_tokens"),cacheRead:n("cache_read_input_tokens"),cacheWrite:n("cache_creation_input_tokens"))
  }
  return Reported(model:nil,input:nil,output:nil,cacheRead:nil,cacheWrite:nil)
 }

 static func entry(who: String,job: String,started: Date,ended: Date,ok: Bool,data: Data) -> UsageEntry {
  let r = reported(from:data)
  return UsageEntry(id:UUID().uuidString,at:started,who:who,job:job,seconds:max(0,ended.timeIntervalSince(started)),ok:ok,
                    model:r.model,inputTokens:r.input,outputTokens:r.output,cacheReadTokens:r.cacheRead,cacheWriteTokens:r.cacheWrite)
 }

 struct Summary: Equatable { var runs: Int; var failed: Int; var notReported: Int; var tokensIn: Int; var tokensOut: Int; var seconds: Double }

 // Sums ONLY the runs that reported numbers; the rest are counted in notReported, never added as zero.
 static func summary(_ entries: [UsageEntry],since: Date) -> Summary {
  let e = entries.filter { $0.at >= since }
  let rep = e.filter { $0.reported }
  return Summary(runs:e.count,failed:e.filter { !$0.ok }.count,notReported:e.count - rep.count,
                 tokensIn:rep.compactMap { $0.tokensIn }.reduce(0,+),tokensOut:rep.compactMap { $0.outputTokens }.reduce(0,+),
                 seconds:e.map { $0.seconds }.reduce(0,+))
 }

 static func tokens(_ n: Int) -> String {
  n >= 1_000_000 ? String(format:"%.1fM",Double(n) / 1_000_000) : (n >= 1000 ? String(format:"%.1fk",Double(n) / 1000) : "\(n)")
 }

 static func line(_ s: Summary,label: String) -> String {
  if s.runs == 0 { return "\(label): no engine runs" }
  // Roxy's rule (11-06): what a non-technical reader sees first is how many runs actually reported numbers.
  let rep = s.runs - s.notReported
  var t = "\(label): \(s.runs) run\(s.runs == 1 ? "" : "s") · tokens reported for \(rep) of \(s.runs)"
  if rep > 0 { t += " · \(tokens(s.tokensIn)) in · \(tokens(s.tokensOut)) out" }
  if s.failed > 0 { t += " · \(s.failed) not proven" }   // !ok = didn't finish OR delivery not proven: not always "failed"
  return t
 }
}

@MainActor final class UsageLedger: ObservableObject {
 static let shared = UsageLedger()
 @Published private(set) var entries: [UsageEntry] = []

 // Per app ID, like the Switchboard: a test copy never writes the real Helm's ledger.
 private let url: URL = {
  let base = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
  let dir = base.appendingPathComponent("UsageLedger-\(Bundle.main.bundleIdentifier ?? "helm")",isDirectory:true)
  try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  return dir.appendingPathComponent("ledger.json")
 }()

 init() {
  let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
  if let d = try? Data(contentsOf:url), let v = try? dec.decode([UsageEntry].self,from:d) { entries = v }
 }

 func record(who: String,job: String,started: Date,ok: Bool,data: Data) {
  entries.append(UsageLedgerRules.entry(who:who,job:job,started:started,ended:Date(),ok:ok,data:data))
  if entries.count > UsageLedgerRules.keep { entries.removeFirst(entries.count - UsageLedgerRules.keep) }
  let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
  if let d = try? enc.encode(entries) { try? d.write(to:url,options:.atomic) }
 }
}

// Three plain lines under the Switchboard panel: today, the last 7 days, and the newest run.
struct UsageLedgerSummary: View {
 @ObservedObject var ledger = UsageLedger.shared
 var compact = false   // compact (Simple mode): just today's line
 private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f }()

 var body: some View {
  let now = Date()
  let today = UsageLedgerRules.summary(ledger.entries,since:Calendar.current.startOfDay(for:now))
  let week = UsageLedgerRules.summary(ledger.entries,since:now.addingTimeInterval(-7 * 86400))
  if compact {
   Text("Usage · " + UsageLedgerRules.line(today,label:"today")).font(.system(size:11)).foregroundStyle(HubTheme.subtext).lineLimit(1)
  } else {
  VStack(alignment:.leading,spacing:3) {
   Text("USAGE · reported usage only").font(.system(size:10,weight:.medium,design:.monospaced)).tracking(1.1).foregroundStyle(HubTheme.subtext)
   Text(UsageLedgerRules.line(today,label:"Today")).font(.system(size:11.5)).foregroundStyle(HubTheme.text)
   Text(UsageLedgerRules.line(week,label:"7 days")).font(.system(size:11.5)).foregroundStyle(HubTheme.text)
   if let last = ledger.entries.last {
    Text("Newest: \(last.who) \(last.job) at \(Self.time.string(from:last.at)) · \(Int(last.seconds.rounded())) s · "
         + (last.reported ? "\(UsageLedgerRules.tokens(last.tokensIn ?? 0)) in, \(UsageLedgerRules.tokens(last.outputTokens ?? 0)) out" : "not reported")
         + (last.ok ? "" : " · not proven"))
     .font(.system(size:11)).foregroundStyle(HubTheme.subtext).lineLimit(1)
   }
   Text("Counts what The Helm started on this Mac. No prices: on a Max plan these use your plan's limits.")
    .font(.system(size:10.5)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
  }
  .accessibilityElement(children:.combine)
  }
 }
}
