import Foundation

// Offline check of GitHub's rate-limit header parsing and the plain message. Run: zsh checks/run.sh
@main struct GitHubReadCheck {
 static var failures = 0
 static func expect(_ ok: Bool,_ what: String) { print((ok ? "PASS " : "FAIL ") + what); if !ok { failures += 1 } }
 static func main() {
  // 403 + remaining 0 + reset  ->  limited, with the right local time (reset 1793961369 = 6:36 AM in Moncton)
  let forbidden = "HTTP/2.0 403 Forbidden\r\nx-ratelimit-limit: 60\r\nx-ratelimit-remaining: 0\r\nx-ratelimit-reset: 1793961369\r\n\r\n{\"message\":\"API rate limit exceeded\"}"
  let r403 = GitHubRead.parseGhOutput(Data(forbidden.utf8))
  expect(r403?.status == 403 && r403?.remaining == 0,"parses a 403 with remaining 0")
  let until = r403.flatMap { GitHubRead.limitReset(status:$0.status,remaining:$0.remaining,reset:$0.reset) }
  expect(until != nil,"403 + remaining 0 + reset = limited")
  expect(GitHubRead.limitMessage(until) == "GitHub's free limit is used up. Trying again at 6:36 AM.","message has the right local time")
  // 200 -> no message; body and link survive
  let ok = "HTTP/2.0 200 OK\nlink: <https://api.github.com/x?page=3>; rel=\"last\"\nx-ratelimit-remaining: 4991\n\n[{\"id\":1}]"
  let r200 = GitHubRead.parseGhOutput(Data(ok.utf8))
  expect(r200?.status == 200,"parses a 200")
  expect(r200.flatMap { GitHubRead.limitReset(status:$0.status,remaining:$0.remaining,reset:$0.reset) } == nil,"200 is not limited")
  expect(GitHubRead.limitMessage(nil) == nil,"no limit = no message")
  expect(String(data:r200?.body ?? Data(),encoding:.utf8) == "[{\"id\":1}]","body kept")
  expect(r200?.link?.contains("rel=\"last\"") == true,"link header kept")
  // other 403 (not out of reads) is not the limit message
  expect(GitHubRead.limitReset(status:403,remaining:12,reset:Date()) == nil,"403 with reads left is not the limit")
  expect(GitHubRead.parseGhOutput(Data("not http".utf8)) == nil,"garbage is rejected")
  print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
  exit(failures == 0 ? 0 : 1)
 }
}
