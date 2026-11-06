// Offline checks for the usage ledger's rules (NB2, 2026-11-06). Run by checks/run.sh.
import Foundation

var failures = 0
func expect(_ ok: Bool,_ what: String) { print((ok ? "PASS  " : "FAIL  ") + what); if !ok { failures += 1 } }

// A json-mode result object, shaped like the engine's real one (numbers made up for the test).
let jsonOut = #"{"type":"result","is_error":false,"result":"pong","usage":{"input_tokens":12,"output_tokens":5,"cache_read_input_tokens":3000,"cache_creation_input_tokens":200},"modelUsage":{"claude-sonnet-x":{"inputTokens":12}},"total_cost_usd":0.01}"#
let r = UsageLedgerRules.reported(from:Data(jsonOut.utf8))
expect(r.input == 12 && r.output == 5 && r.cacheRead == 3000 && r.cacheWrite == 200,"json result: tokens read from the engine's own usage block")
expect(r.model == "claude-sonnet-x","json result: model from modelUsage keys")

// stream-json: many lines, the result is the last one.
let stream = #"{"type":"system","subtype":"init"}"# + "\n" + #"{"type":"assistant","message":{}}"# + "\n" + #"{"type":"result","usage":{"input_tokens":7,"output_tokens":2}}"#
let s = UsageLedgerRules.reported(from:Data(stream.utf8))
expect(s.input == 7 && s.output == 2 && s.model == nil,"stream-json: last result line read; no modelUsage = model nil, not guessed")

// Nothing reported: nil, never 0.
let none = UsageLedgerRules.reported(from:Data("garbage\n{\"type\":\"result\",\"result\":\"x\"}".utf8))
expect(none.input == nil && none.output == nil,"a result without usage gives nil (not reported), never 0")
expect(UsageLedgerRules.reported(from:Data()).input == nil,"empty output gives nil")

let t0 = Date(timeIntervalSince1970:1_800_000_000)
let a = UsageLedgerRules.entry(who:"Friday (brain)",job:"sonnet",started:t0,ended:t0.addingTimeInterval(4.5),ok:true,data:Data(jsonOut.utf8))
let b = UsageLedgerRules.entry(who:"Wake",job:"LC-Pixels",started:t0.addingTimeInterval(10),ended:t0.addingTimeInterval(40),ok:false,data:Data("no json".utf8))
expect(a.seconds == 4.5 && a.tokensIn == 3212 && a.reported,"entry: seconds measured; tokens in = input + cache read + cache write")
expect(!b.reported && b.tokensIn == nil,"entry without numbers is marked not reported")

// No prices and no message text are ever stored.
let enc = String(decoding:try! JSONEncoder().encode(a),as:UTF8.self)
expect(!enc.contains("cost") && !enc.contains("0.01"),"no dollar figure is stored")
expect(!enc.contains("pong"),"the answer text is never stored")

let sum = UsageLedgerRules.summary([a,b],since:t0)
expect(sum.runs == 2 && sum.notReported == 1 && sum.tokensIn == 3212 && sum.tokensOut == 5 && sum.failed == 1,"summary: unreported run counted apart, not added as zero")
let line = UsageLedgerRules.line(sum,label:"Today")
expect(line.hasPrefix("Today: 2 runs · tokens reported for 1 of 2") && line.contains("1 not proven"),"summary line leads with runs and how many reported: \(line)")
let onlyUnknown = UsageLedgerRules.line(UsageLedgerRules.summary([b],since:t0),label:"Today")
expect(onlyUnknown.contains("1 not proven") && onlyUnknown.contains("reported for 0 of 1") && !onlyUnknown.contains(" in ·") && !onlyUnknown.contains("0 in"),"when no run reported, no '0 tokens' figure is shown: \(onlyUnknown)")
expect(UsageLedgerRules.line(UsageLedgerRules.summary([],since:t0),label:"7 days") == "7 days: no engine runs","empty week says so plainly")
expect(UsageLedgerRules.summary([a],since:t0.addingTimeInterval(1)).runs == 0,"runs before the window are left out")

print(failures == 0 ? "ALL PASS (usage ledger)" : "\(failures) FAILED (usage ledger)")
if failures > 0 { exit(1) }
