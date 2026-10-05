import Foundation

// Checks for the pieces that need no Mac frameworks: the highlight cut, the board reader and the Stripe reader's key rules.
// Run on any machine with Swift:
//   swiftc -parse-as-library ClipMath.swift MeetingData.swift StripeData.swift checks/DataChecks.swift -o /tmp/data-checks && /tmp/data-checks
@main struct DataChecks {
 static func main() {
  let hop = 0.25
  // A 30 second clip with a loud burst from 18 to 24 seconds keeps that burst plus a beat either side.
  var burst = [Float](repeating:0.02,count:120)
  for i in 72..<96 { burst[i] = 0.6 }
  let cut = ClipMath.highlight(levels:burst,hop:hop,maxLength:25)!
  precondition(abs(cut.start - 16.5) < 0.01 && abs(cut.end - 26.0) < 0.01)
  // Two bursts and a short limit: the bigger, later one wins.
  var two = [Float](repeating:0.02,count:120)
  for i in 12..<16 { two[i] = 0.3 }
  for i in 80..<92 { two[i] = 0.7 }
  let later = ClipMath.highlight(levels:two,hop:hop,maxLength:8)!
  precondition(later.start > 15 && later.length <= 8)
  // Silence: nothing to go on, so keep the most recent stretch.
  let quiet = ClipMath.highlight(levels:[Float](repeating:0,count:120),hop:hop,maxLength:25)!
  precondition(abs(quiet.end - 30) < 0.01 && abs(quiet.length - 25) < 0.01)
  precondition(ClipMath.highlight(levels:[],hop:hop,maxLength:25) == nil)
  // Whatever the input, the cut stays inside the clip and never exceeds the limit (or the 6 second minimum).
  for _ in 0..<500 {
   let n = Int.random(in:8...240)
   let levels = (0..<n).map { _ in Float.random(in:0...1) * (Bool.random() ? 0.05 : 0.9) }
   let limit = Double.random(in:8...40)
   let result = ClipMath.highlight(levels:levels,hop:hop,maxLength:limit)!
   precondition(result.start >= 0 && result.end <= Double(n) * hop + 1e-9 && result.length > 0 && result.length <= max(limit,6) + 1e-6)
  }

  // The board: owner, text and status are pulled apart; an indented line continues the item above; done items aren't open.
  let board = MeetingData.parse("# T\n_Last updated: x by y_\n## On the table\n- [A] one\n  more. Status: Done.\n- [B → C] two. Status: building\n## Q\n- hi\n")
  precondition(board.sections.count == 2 && board.updated == "x by y")
  let first = board.sections[0].items[0]
  precondition(first.owner == "A" && first.text == "one more." && first.isDone)
  precondition(board.sections[0].items[1].owner == "B → C" && board.openCount == 1)
  precondition(MeetingData.parse("").sections.isEmpty)

  // Stripe: only a restricted read-only key is accepted.
  precondition(StripeData.keyProblem("sk_live_abc") != nil && StripeData.keyProblem("pk_live_abc") != nil)
  precondition(StripeData.keyProblem("rk_live_abc") == nil && StripeData.keyProblem("rk_test_abc") == nil)
  print("All data checks passed.")
 }
}
