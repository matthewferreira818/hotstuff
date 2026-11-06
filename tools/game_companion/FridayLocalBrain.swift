import Foundation
import Darwin

// Friday's offline backup brain (Matthew's GO 2026-11-06 ~1:45 PM; plan agreed with NB2). Roadmap Phase 6, $0, nothing installed.
// WHEN: only for Friday's typed chat, and only when the Claude brain truly can't run: its engine isn't found, Claude's usage limit is
//       reached, or Guard's Offline mode is on. Never for Switchboard jobs, relays or wakes (they need tools and proof), and never just because
//       Claude is slow.
// WHERE: Ollama on THIS Mac only. The address is a constant (127.0.0.1:11434) and LocalBrainRules.isLocal refuses anything else, so it is
//        not an internet call and Offline mode stays true.
// HOW: the model loads on demand and unloads after keepAlive; if free memory is under minFreeGB it says so instead of slowing the Mac.
//      Smaller context than Claude's, no tools, the strictest honesty rules, and every answer is labelled with which brain wrote it.
// Usage: one UsageLedger line ("Friday (local brain)"), tokens only from Ollama's own prompt_eval_count / eval_count.
// Matthew can change the settings below (model, memory floor, how long it stays loaded); the honesty rules and the local-only address stay.

enum LocalBrainRules {
 // Settings (his to change)
 static let model = "gemma3:4b"
 static let keepAlive = "2m"
 static let minFreeGB = 3.0
 static let timeout: TimeInterval = 90
 static let contextCap = 3000          // characters of context: about half of Claude's pack, so a 4B model stays focused

 // Fixed
 static let base = "http://127.0.0.1:11434"
 static let label = "(Offline brain · Gemma on this Mac)"

 static func url(_ path: String) -> URL? {
  guard let u = URL(string:base + path), isLocal(u) else { return nil }
  return u
 }
 static func isLocal(_ u: URL) -> Bool { u.scheme == "http" && u.host == "127.0.0.1" && u.port == 11434 }

 // Claude's own words when a plan's limit is reached (seen in the CLI's result text). Lower-cased match.
 static func limitHit(_ data: Data) -> Bool {
  let t = String(decoding:data,as:UTF8.self).lowercased()
  return ["usage limit","limit reached","hit your limit","you've reached your"]   // not "rate limit": a short hiccup isn't a reason to switch brains.contains { t.contains($0) }
 }

 static let system = """
 You are Friday, Matthew's own AI: warm, plain words, short answers, opinions with reasons. Right now you are running as a SMALL OFFLINE \
 model on his Mac because the main Claude brain can't run. Rules you never break:
 - You have no tools. Never say you did, checked, opened, sent, posted, saved or changed anything.
 - Use only the context and chat given. If you don't know, say "I don't know" plainly. Never invent numbers, names, dates or facts.
 - No money, logins, passwords or messages to people.
 - Keep it short: two to five sentences.
 """

 static func trimmedContext(_ context: String) -> String { String(context.prefix(contextCap)) }

 static func body(context: String,history: String,question: String) -> Data? {
  var user = "CONTEXT (from The Helm, on this Mac):\n\(trimmedContext(context))\n\n"
  if !history.isEmpty { user += "RECENT CHAT:\n\(history)\n\n" }
  user += "MATTHEW'S MESSAGE:\n\(String(question.prefix(FridayBrainLimits.questionCap)))"
  let json: [String:Any] = ["model":model,"stream":false,"keep_alive":keepAlive,
                            "messages":[["role":"system","content":system],["role":"user","content":user]],
                            "options":["num_ctx":4096,"temperature":0.4]]
  return try? JSONSerialization.data(withJSONObject:json)
 }

 struct Reply: Equatable { var text: String?; var promptTokens: Int?; var outputTokens: Int? }
 static func parse(_ data: Data) -> Reply {
  guard let j = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else { return Reply(text:nil,promptTokens:nil,outputTokens:nil) }
  let text = ((j["message"] as? [String:Any])?["content"] as? String)?.trimmingCharacters(in:.whitespacesAndNewlines)
  return Reply(text:(text?.isEmpty ?? true) ? nil : text,promptTokens:(j["prompt_eval_count"] as? NSNumber)?.intValue,outputTokens:(j["eval_count"] as? NSNumber)?.intValue)
 }

 // A ledger line in the same shape the ledger already reads (the "result" object), so UsageLedger needs no change.
 // Keys are only written when Ollama reported them: a missing key stays "not reported".
 static func ledgerData(_ r: Reply) -> Data {
  var usage: [String:Any] = [:]
  if let p = r.promptTokens { usage["input_tokens"] = p }
  if let o = r.outputTokens { usage["output_tokens"] = o }
  var j: [String:Any] = ["type":"result","modelUsage":[model + " (local)":[String:Any]()]]
  if !usage.isEmpty { j["usage"] = usage }
  return (try? JSONSerialization.data(withJSONObject:j)) ?? Data()
 }
}

enum LocalBrainMemory {
 // macOS's own "memory free" percentage (the same number `memory_pressure` prints), as GB of this Mac's memory.
 // Falls back to free + inactive + speculative + purgeable pages if the kernel doesn't say.
 static func availableGB() -> Double? {
  var level: Int32 = 0
  var size = MemoryLayout<Int32>.size
  if sysctlbyname("kern.memorystatus_level",&level,&size,nil,0) == 0, level > 0, level <= 100 {
   return Double(level) / 100 * Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
  }
  return pagesAvailableGB()
 }
 static func pagesAvailableGB() -> Double? {
  var vm = vm_statistics64()
  var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
  let r = withUnsafeMutablePointer(to:&vm) { $0.withMemoryRebound(to:integer_t.self,capacity:Int(count)) { host_statistics64(mach_host_self(),HOST_VM_INFO64,$0,&count) } }
  guard r == KERN_SUCCESS else { return nil }
  let pages = Double(vm.free_count) + Double(vm.inactive_count) + Double(vm.speculative_count) + Double(vm.purgeable_count)
  return pages * Double(getpagesize()) / 1_073_741_824
 }
}

@MainActor enum FridayLocalBrain {
 // Returns an answer for the chat box. `why` is the plain reason Claude couldn't run; it goes in the grey note under the answer.
 static func answer(question: String,history: String,context: String,why: String) async -> FridayBrainRules.Answer {
  let note = "Claude couldn't run (\(why)), so Gemma answered here on this Mac. Nothing left the Mac."
  if let free = LocalBrainMemory.availableGB(), free < LocalBrainRules.minFreeGB {
   return .init(ok:false,text:"I can't think offline right now: memory is tight (\(String(format:"%.1f",free)) GB free). Close an app or two and ask again.",note:"Claude couldn't run (\(why))")
  }
  guard let url = LocalBrainRules.url("/api/chat"), let body = LocalBrainRules.body(context:context,history:history,question:question) else {
   return .init(ok:false,text:"I can't think offline right now: my offline brain's address didn't pass its own safety check.",note:nil)
  }
  var request = URLRequest(url:url,timeoutInterval:LocalBrainRules.timeout)
  request.httpMethod = "POST"
  request.setValue("application/json",forHTTPHeaderField:"Content-Type")
  request.httpBody = body
  let began = Date()
  do {
   let (data,response) = try await URLSession.shared.data(for:request)
   let reply = LocalBrainRules.parse(data)
   let ok = (response as? HTTPURLResponse)?.statusCode == 200 && reply.text != nil
   UsageLedger.shared.record(who:"Friday (local brain)",job:LocalBrainRules.model,started:began,ok:ok,data:LocalBrainRules.ledgerData(reply))
   guard ok, let text = reply.text else {
    return .init(ok:false,text:"I can't think offline right now: Ollama answered, but not with words. Is the \(LocalBrainRules.model) model still installed?",note:"Claude couldn't run (\(why))")
   }
   let plain = text.replacingOccurrences(of:"**",with:"").replacingOccurrences(of:"`",with:"")
   // Same place as the Claude path: a "she claims she did something" warning goes in the grey note, not in her words.
   let tool = FridayBrainRules.claimsOwnAction(plain) ? " · " + FridayBrainRules.toolNote : ""
   return .init(ok:true,text:LocalBrainRules.label + " " + plain,note:note + tool)
  } catch {
   UsageLedger.shared.record(who:"Friday (local brain)",job:LocalBrainRules.model,started:began,ok:false,data:Data())
   return .init(ok:false,text:"I can't think offline right now: Ollama isn't answering on this Mac. Open the Ollama app and ask again.",note:"Claude couldn't run (\(why))")
  }
 }
}
