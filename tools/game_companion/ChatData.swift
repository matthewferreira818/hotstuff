import Foundation

// The chat helper's rules, with no Mac frameworks so they can be tested anywhere. The helper posts Matthew's own saved messages
// (his links and reminders such as "use your Prime sub") in his Twitch chat while he is live. It never writes anything else:
// the text is always one of his saved messages, never something the model or a chat viewer made up.
// Twitch's Send Chat Message call was checked against dev.twitch.tv/docs/api/reference on 2026-10-05: user:write:chat, at most
// 500 characters, sender must be the signed-in account, and 200 can still come back with is_sent false and a drop reason.

struct ChatTimer: Codable, Identifiable, Equatable {
 var id: String
 var name: String
 var text: String
 var minutes: Int
 var enabled: Bool
}

enum ChatPlan {
 static let maxLength = 500
 static let minMinutes = 10
 static let maxMinutes = 180
 // Between any two posts by the helper, and the most it will post in an hour.
 static let gapMinutes = 5
 static let hourlyCap = 6

 // Starting messages. Nothing posts until Matthew turns the helper on. The Prime line describes Twitch's own Prime sub; he can edit it.
 static func defaults() -> [ChatTimer] {
  [
   ChatTimer(id:"store",name:"My store",text:"Check out my store: https://findhotstuff.com",minutes:20,enabled:true),
   ChatTimer(id:"prime",name:"Prime sub",text:"Have Amazon Prime? You get one free channel sub a month. Link Prime to Twitch and use it here: https://www.twitch.tv/subs/{channel}",minutes:30,enabled:true),
   ChatTimer(id:"follow",name:"Follow",text:"Enjoying the stream? Hit Follow so you know when I go live.",minutes:40,enabled:true),
   ChatTimer(id:"ecs",name:"East Coast Social",text:"I also run East Coast Social: daily social media posts for local New Brunswick businesses. https://findhotstuff.com/automation",minutes:60,enabled:false)
  ]
 }

 static func render(_ text: String,channel: String) -> String {
  text.replacingOccurrences(of:"{channel}",with:channel).trimmingCharacters(in:.whitespacesAndNewlines)
 }

 // nil when the message is fine to post. A leading / or . could be read as a chat command, so those are refused.
 static func problem(_ text: String) -> String? {
  let clean = text.trimmingCharacters(in:.whitespacesAndNewlines)
  if clean.isEmpty { return "Type the message first." }
  if clean.count > maxLength { return "That message is \(clean.count) characters. Twitch's limit is \(maxLength)." }
  if clean.hasPrefix("/") || clean.hasPrefix(".") { return "A message can't start with / or . (Twitch could read it as a chat command)." }
  return nil
 }

 static func clampMinutes(_ value: Int) -> Int { min(max(value,minMinutes),maxMinutes) }

 // Which saved message should go out now, or nil. Rules: at least `gapMinutes` since the last helper post (or since it was turned
 // on, so nothing posts the moment it starts), no more than `hourlyCap` in the last hour, and each message waits its own number of
 // minutes. If several are due, the one that has waited longest goes first.
 static func next(_ timers: [ChatTimer],lastPosted: [String:Date],startedAt: Date,lastAny: Date?,posts: [Date],now: Date) -> ChatTimer? {
  if now.timeIntervalSince(lastAny ?? startedAt) < Double(gapMinutes * 60) { return nil }
  if posts.filter({ now.timeIntervalSince($0) < 3600 }).count >= hourlyCap { return nil }
  var best: (timer: ChatTimer,overdue: TimeInterval)?
  for timer in timers where timer.enabled && problem(timer.text) == nil {
   let waited = now.timeIntervalSince(lastPosted[timer.id] ?? startedAt)
   let overdue = waited - Double(clampMinutes(timer.minutes) * 60)
   if overdue >= 0, best == nil || overdue > best!.overdue { best = (timer,overdue) }
  }
  return best?.timer
 }

 static func sendBody(broadcaster: String,sender: String,message: String) -> Data? {
  try? JSONSerialization.data(withJSONObject:["broadcaster_id":broadcaster,"sender_id":sender,"message":message])
 }

 // What Twitch's answer means in plain words.
 static func outcome(code: Int,json: [String:Any]) -> (sent: Bool,note: String) {
  switch code {
  case 200:
   let row = (json["data"] as? [[String:Any]])?.first
   if row?["is_sent"] as? Bool == true { return (true,"Posted.") }
   let reason = ((row?["drop_reason"] as? [String:Any])?["message"] as? String) ?? "Twitch held it back."
   return (false,"Twitch didn't post it: \(reason)")
  case 401: return (false,"Twitch needs one more permission to chat. Open Accounts, sign out of Twitch, then sign in again.")
  case 403: return (false,"Twitch won't let this account chat in your channel right now.")
  case 422: return (false,"That message is too long for Twitch.")
  case 429: return (false,"Twitch says slow down. It will try again later.")
  default: return (false,"Couldn't post (Twitch answered \(code)).")
  }
 }
}
