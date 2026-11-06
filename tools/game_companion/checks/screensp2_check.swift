import Foundation
// Offline check of the Phase 2 screen rules (ScreensP2Data.swift). Run: zsh checks/run.sh
var fails = 0
func check(_ n: String,_ c: Bool){ print(c ? "PASS" : "FAIL", n); if !c {fails+=1} }
check("targets: 4 fixed doors first", ComposerRules.targets(openChats:[]) == ["Everyone","Claude","Friday","LC-Manager"])
check("targets: open LCs added once, sorted, plain", ComposerRules.targets(openChats:["LC-Trends","Local Claude (LC-Pixels)","LC-Manager","lc-trends"]) == ["Everyone","Claude","Friday","LC-Manager","LC-Pixels","LC-Trends"])
check("body keeps the arrow even for Everyone", ComposerRules.body(to:"Everyone",text:" hi there ") == "**[Matthew → Everyone]** hi there")
check("body to an LC", ComposerRules.body(to:"LC-Manager",text:"go") == "**[Matthew → LC-Manager]** go")
check("empty text -> nil", ComposerRules.body(to:"Claude",text:"  \n ") == nil)
check("comment id parsed", ComposerRules.commentID("{\"id\":6684186989,\"body\":\"x\"}".data(using:.utf8)!) == 6684186989)
check("garbage -> nil id", ComposerRules.commentID("nope".data(using:.utf8)!) == nil)

let file = """
# Header line stays

## Format
- text

## Entries (oldest first)

### m-20261106-01
tag: About Matthew
saved: 2026-11-06 06:40
by: Matthew
important: yes
text: Her name is Friday.

### m-20261106-02
tag: Moods
saved: 2026-11-06 06:30
by: Friday
important: no
text: He was stressed about the call.

### m-20261106-03
tag: Likes
saved: 2026-11-06 06:45
by: Friday
important: no
text: Likes short answers.

"""
let es = MemoryBank.parse(file)
check("parse: 3 entries", es.count == 3 && es[1].id == "m-20261106-02")
check("parse: fields", es[0].important && es[0].by == "Matthew" && es[0].saved == "2026-11-06 06:40" && !es[2].important)
check("parse: mood flagged private", es[1].isMood && !es[0].isMood)
let kept = MemoryBank.keep(file,id:"m-20261106-03")!
check("keep sets important yes on that entry only", MemoryBank.parse(kept)[2].important && !MemoryBank.parse(kept)[1].important && kept.hasPrefix("# Header line stays"))
let edited = MemoryBank.edit(file,id:"m-20261106-03",text:"Likes short answers.\nAnd plain words.",tag:"How he talks")!
let e2 = MemoryBank.parse(edited)
check("edit: text on one line, tag changed, id kept", e2[2].text == "Likes short answers. And plain words." && e2[2].tag == "How he talks" && e2[2].id == "m-20261106-03")
check("edit: other entries untouched", e2[0] == es[0] && e2[1] == es[1])
check("edit: empty text refused", MemoryBank.edit(file,id:"m-20261106-03",text:"  ") == nil)
check("edit: unknown tag ignored", MemoryBank.parse(MemoryBank.edit(file,id:"m-20261106-03",text:"x",tag:"Nope")!)[2].tag == "Likes")
let gone = MemoryBank.forget(file,id:"m-20261106-02")!
let g = MemoryBank.parse(gone)
check("forget: block deleted, others stay", g.count == 2 && g.map { $0.id } == ["m-20261106-01","m-20261106-03"] && !gone.contains("stressed"))
check("forget: header above the first ### untouched", gone.hasPrefix("# Header line stays\n\n## Format\n- text\n\n## Entries (oldest first)\n\n### m-20261106-01"))
check("forget: unknown id -> nil", MemoryBank.forget(file,id:"m-nope") == nil)
check("forget the last entry is clean", MemoryBank.parse(MemoryBank.forget(file,id:"m-20261106-03")!).count == 2)
check("forget then parse is stable (round trip)", MemoryBank.parse(MemoryBank.forget(MemoryBank.forget(file,id:"m-20261106-01")!,id:"m-20261106-02")!).map { $0.id } == ["m-20261106-03"])

let mm = """
# One Money Move
Rules: x

## 2026-11-05 (Thu)
move: Old one.
why: old why

## 2026-11-06 (Fri)
move: Fill in the 7 blanks.
why: CBDC's answer unlocks every sale.
"""
let m = MoneyMoveFile.latest(mm)
check("money move: newest section wins", m?.date == "2026-11-06" && m?.move == "Fill in the 7 blanks." && m?.why == "CBDC's answer unlocks every sale.")
check("money move: file order doesn't matter", MoneyMoveFile.latest("## 2026-11-06\nmove: new\n\n## 2026-11-05\nmove: old\n")?.move == "new")
check("money move: none -> nil", MoneyMoveFile.latest("# nothing\nRules: x\n") == nil)
check("money move: section without a move ignored", MoneyMoveFile.latest("## 2026-11-07\nwhy: only why\n\n## 2026-11-06\nmove: real\n")?.date == "2026-11-06")
check("as-of wording", MoneyMoveFile.asOf("2026-11-06") == "Friday, Nov 6")

check("thinking: sent, no reply, waiting", DMScreenRules.thinking(lastSentID:"a",repliedTo:[],state:"woken"))
check("thinking: replied -> not thinking", !DMScreenRules.thinking(lastSentID:"a",repliedTo:["a"],state:"woken"))
check("thinking: closed -> not thinking", !DMScreenRules.thinking(lastSentID:"a",repliedTo:[],state:"closed"))
check("thinking: failed -> not thinking", !DMScreenRules.thinking(lastSentID:"a",repliedTo:[],state:"failed"))
check("thinking: nothing sent -> not thinking", !DMScreenRules.thinking(lastSentID:nil,repliedTo:[],state:nil))
exit(fails == 0 ? 0 : 1)
