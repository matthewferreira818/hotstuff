import Foundation
// Offline brain rules: run by checks/run.sh (LocalBrainRules is pulled out of FridayLocalBrain.swift with a FridayBrainLimits stub).
var fails = 0
func check(_ ok: Bool,_ name: String) { print(ok ? "PASS \(name)" : "FAIL \(name)"); if !ok { fails += 1 } }

check(LocalBrainRules.url("/api/chat")?.absoluteString == "http://127.0.0.1:11434/api/chat","the only address is this Mac's Ollama")
check(!LocalBrainRules.isLocal(URL(string:"http://example.com:11434/api/chat")!),"another host is refused")
check(!LocalBrainRules.isLocal(URL(string:"https://127.0.0.1:11434/api/chat")!),"another scheme is refused")
check(!LocalBrainRules.isLocal(URL(string:"http://127.0.0.1:8080/api/chat")!),"another port is refused")
check(!LocalBrainRules.isLocal(URL(string:"http://localhost.evil.com:11434/")!),"a lookalike host is refused")
check(LocalBrainRules.limitHit(Data(#"{"type":"result","is_error":true,"result":"Claude AI usage limit reached|1793980000"}"#.utf8)),"usage limit text is spotted")
check(LocalBrainRules.limitHit(Data("You've hit your limit · resets 3pm".utf8)),"'hit your limit' is spotted")
check(!LocalBrainRules.limitHit(Data(#"{"type":"result","result":"Here are the robots"}"#.utf8)),"a normal answer is not a limit")
check(!LocalBrainRules.limitHit(Data(#"{"type":"result","is_error":true,"result":"API Error: rate limit, retrying"}"#.utf8)),"a short rate-limit hiccup does not switch brains")
let r = LocalBrainRules.parse(Data(#"{"message":{"role":"assistant","content":"  Hi boss. "},"prompt_eval_count":812,"eval_count":40,"done":true}"#.utf8))
check(r.text == "Hi boss." && r.promptTokens == 812 && r.outputTokens == 40,"reply text and Ollama's own counts are read")
let empty = LocalBrainRules.parse(Data(#"{"message":{"content":"   "}}"#.utf8))
check(empty.text == nil && empty.promptTokens == nil,"an empty reply is no answer, and missing counts stay missing")
let led = String(decoding:LocalBrainRules.ledgerData(LocalBrainRules.Reply(text:"x",promptTokens:nil,outputTokens:nil)),as:UTF8.self)
check(led.contains("\"result\"") && !led.contains("usage") && led.contains("(local)"),"no counts reported -> no usage key (ledger says 'not reported', never 0)")
let led2 = String(decoding:LocalBrainRules.ledgerData(LocalBrainRules.Reply(text:"x",promptTokens:5,outputTokens:7)),as:UTF8.self)
check(led2.contains("\"input_tokens\":5") && led2.contains("\"output_tokens\":7"),"reported counts go in the ledger's own shape")
let body = String(decoding:LocalBrainRules.body(context:String(repeating:"c",count:9000),history:"",question:"hi")!,as:UTF8.self)
check(body.contains("gemma3:4b") && body.contains("\"keep_alive\":\"2m\"") && body.contains("\"stream\":false"),"model, short keep-alive, no streaming")
check(!body.contains(String(repeating:"c",count:3001)),"context is capped")
check(LocalBrainRules.system.contains("no tools") && LocalBrainRules.system.contains("I don't know"),"strict honesty rules are in the system prompt")
check(LocalBrainRules.label.contains("Offline brain") && LocalBrainRules.label.contains("on this Mac"),"every answer is labelled")
print(fails == 0 ? "ALL PASS (offline brain)" : "\(fails) FAILED (offline brain)")
