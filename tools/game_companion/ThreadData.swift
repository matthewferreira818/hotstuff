import Foundation

// How the Meeting Room's Thread tab lays out the room's messages: newest first, grouped by day (Today, Yesterday, This week, Earlier),
// with an optional filter to one sender. Foundation-only so it can be tested here; the page itself is in MeetingRoom.swift.

struct DayGroup: Identifiable {
 var title: String
 var messages: [RoomMessage]
 var id: String { title }
}

enum ThreadData {
 static let senders = ["All","Claude","GPT","Friday","Matthew"]
 static let dayTitles = ["Today","Yesterday","This week","Earlier"]

 // Only the messages from this sender (any letter case); "All" keeps everything.
 static func filtered(_ messages: [RoomMessage],sender: String) -> [RoomMessage] {
  guard sender != "All" else { return messages }
  return messages.filter { MeetingData.same($0.author,sender) }
 }

 // Which group a date belongs to. A message with no date, or one older than a week, is "Earlier". A date in the future counts as today.
 static func dayTitle(_ date: Date?,now: Date,calendar: Calendar) -> String {
  guard let date = date else { return "Earlier" }
  let startOfToday = calendar.startOfDay(for:now)
  if date >= startOfToday { return "Today" }
  guard let yesterday = calendar.date(byAdding:.day,value:-1,to:startOfToday), let week = calendar.date(byAdding:.day,value:-7,to:startOfToday) else { return "Earlier" }
  if date >= yesterday { return "Yesterday" }
  return date >= week ? "This week" : "Earlier"
 }

 // The newest `limit` messages (after the sender filter), newest first, split into day groups, always in the order Today, Yesterday, This week, Earlier. Empty groups are left out.
 static func dayGroups(_ messages: [RoomMessage],sender: String = "All",limit: Int = 8,now: Date = Date(),calendar: Calendar = Calendar.current) -> [DayGroup] {
  let newest = Array(filtered(messages,sender:sender).reversed().prefix(max(limit,0)))
  var byTitle: [String:[RoomMessage]] = [:]
  for message in newest { byTitle[dayTitle(message.date,now:now,calendar:calendar),default:[]].append(message) }
  return dayTitles.compactMap { title in byTitle[title].map { DayGroup(title:title,messages:$0) } }
 }

 // How many messages the filter leaves, for "Show 8 earlier".
 static func total(_ messages: [RoomMessage],sender: String) -> Int { filtered(messages,sender:sender).count }
}
