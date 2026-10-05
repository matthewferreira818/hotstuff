import Foundation

// Picks the highlight out of a clip, using only how loud it is moment to moment. No AI and no network: the app measures
// the clip's sound (see ClipEditor.swift), and this decides which stretch to keep. A loud stretch is usually the
// action, a shout or the reaction to it; the quiet before and after is the dead air that gets cut.
// Pure maths on a list of numbers, so it is tested on its own (checks/ClipMathChecks.swift).

struct ClipCut: Equatable {
 var start: Double
 var end: Double
 var length: Double { end - start }
}

enum ClipMath {
 // levels: how loud each slice is, 0 to 1, `hop` seconds per slice. Returns the stretch to keep, at most maxLength long.
 // lead and tail give a beat of run-up and aftermath so the cut doesn't start or end mid-sound.
 static func highlight(levels: [Float],hop: Double,maxLength: Double,lead: Double = 1.5,tail: Double = 2.0,minLength: Double = 6) -> ClipCut? {
  guard !levels.isEmpty, hop > 0, maxLength > 0 else { return nil }
  let total = Double(levels.count) * hop
  if total <= minLength { return ClipCut(start:0,end:total) }
  // The clip is made right after the moment, so with nothing to go on the best guess is the most recent stretch.
  let latest = ClipCut(start:max(0,total - maxLength),end:total)
  let peak = levels.max() ?? 0
  guard peak > 0.0005 else { return latest }
  let sorted = levels.sorted()
  let median = sorted[sorted.count / 2]
  // Anything under this counts as quiet.
  let floor = max(median * 1.5,peak * 0.10)
  let energy = levels.map { max(0,Double($0) - Double(floor)) }
  let window = max(1,min(levels.count,Int((maxLength / hop).rounded())))
  var running = energy[0..<window].reduce(0,+)
  var best = running
  var bestStart = 0
  var i = 1
  while i + window <= levels.count {
   running += energy[i + window - 1] - energy[i - 1]
   // On a tie the later window wins: it is the more recent one.
   if running >= best - 1e-9 { best = running; bestStart = i }
   i += 1
  }
  let loud = (bestStart..<(bestStart + window)).filter { levels[$0] > floor }
  guard let first = loud.first, let last = loud.last else { return latest }
  var start = max(0,Double(first) * hop - lead)
  var end = min(total,Double(last + 1) * hop + tail)
  if end - start < minLength {
   // A short burst: grow the cut around it until it is long enough to watch.
   let middle = (start + end) / 2
   start = max(0,middle - minLength / 2)
   end = min(total,start + minLength)
   start = max(0,end - minLength)
  }
  if end - start > maxLength { start = end - maxLength }
  return ClipCut(start:start,end:end)
 }
}
