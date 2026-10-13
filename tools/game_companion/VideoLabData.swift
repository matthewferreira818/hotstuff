import Foundation

// The Video lab's rules, with no Mac frameworks so they can be tested anywhere. Matthew's ask (2026-10-13): "we need to find a way for you
// to analyze videos". Claude (in the cloud chat) can read pictures and words, not play a video, so the lab turns a video file on his Mac into
// both: contact sheets (a grid of frames with their times, small enough to paste into the chat) and a written play-by-play from Google's
// reader (which can hear as well as see). Nothing here posts, saves or sends anything by itself; see VideoLab.swift for what leaves the Mac.

enum VideoLabPlan {
 static let sheetWidth = 2000
 static let gap = 10
 static let labelHeight = 30
 static let headerHeight = 44    // the title line across the top of each sheet
 static let maxSheets = 3
 static let maxWordSeconds = 300.0   // longer than this is too big to send to Google in one go

 // How many pictures to take: enough to follow a short clip, capped so a long video still fits in a few sheets.
 static func frameCount(duration: Double) -> Int {
  guard duration.isFinite, duration > 0 else { return 0 }
  if duration <= 15 { return 12 }
  if duration <= 45 { return 24 }
  if duration <= 120 { return 36 }
  return 48
 }

 // The moments to take pictures at: the middle of each of `count` equal slices of the video, so the first and last pictures are not black
 // fade-in or fade-out frames.
 static func frameTimes(duration: Double,count: Int) -> [Double] {
  guard duration.isFinite, duration > 0, count > 0 else { return [] }
  return (0..<count).map { min(duration,duration * (Double($0) + 0.5) / Double(count)) }
 }

 enum Shape: Equatable { case tall, square, wide }

 // aspect = shown width / shown height (so a TikTok is about 0.56).
 static func shape(aspect: Double) -> Shape {
  if !aspect.isFinite || aspect <= 0 { return .wide }
  if aspect < 0.8 { return .tall }
  return aspect <= 1.25 ? .square : .wide
 }

 static func columns(_ shape: Shape) -> Int {
  switch shape {
  case .tall: return 6
  case .square: return 5
  case .wide: return 4
  }
 }

 // Pictures per sheet, chosen so a sheet is about 2000 wide and not much taller than 2000.
 static func perSheet(_ shape: Shape) -> Int {
  switch shape {
  case .tall: return 18
  case .square: return 15
  case .wide: return 16
  }
 }

 struct Layout: Equatable {
  var columns: Int
  var rows: Int
  var tileWidth: Int
  var tileHeight: Int
  var sheetHeight: Int
 }

 static func layout(count: Int,aspect: Double) -> Layout? {
  guard count > 0 else { return nil }
  let kind = shape(aspect:aspect)
  let full = columns(kind)               // pictures are always the same size, even on a last sheet that has only a few
  let cols = min(count,full)
  let rows = (count + cols - 1) / cols
  let safeAspect = aspect.isFinite && aspect > 0 ? min(3,max(0.3,aspect)) : 16.0 / 9.0
  let tileW = (sheetWidth - gap * (full + 1)) / full
  let tileH = max(1,Int(Double(tileW) / safeAspect))
  return Layout(columns:cols,rows:rows,tileWidth:tileW,tileHeight:tileH,sheetHeight:headerHeight + gap + rows * (tileH + labelHeight + gap))
 }

 // Which pictures go on which sheet, in order. At most `maxSheets` sheets; pictures beyond that are left out (the screen says so).
 static func sheetRanges(total: Int,aspect: Double) -> [Range<Int>] {
  guard total > 0 else { return [] }
  let size = perSheet(shape(aspect:aspect))
  var out: [Range<Int>] = []
  var start = 0
  while start < total && out.count < maxSheets {
   out.append(start..<min(total,start + size))
   start += size
  }
  return out
 }

 // 0:07, 1:05, 1:02:03
 static func label(_ seconds: Double) -> String {
  let whole = max(0,Int(seconds.isFinite ? seconds : 0))
  let h = whole / 3600, m = (whole % 3600) / 60, s = whole % 60
  return h > 0 ? "\(h):" + String(format:"%02d:%02d",m,s) : "\(m):" + String(format:"%02d",s)
 }

 // A folder name made from the video's file name: letters, digits, dash and underscore only, at most 40 characters.
 static func folderName(for file: String,stamp: String) -> String {
  let base = (file as NSString).deletingPathExtension
  let safe = String(base.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }).split(separator:"-",omittingEmptySubsequences:true).joined(separator:"-")
  let trimmed = String(safe.prefix(40))
  return (trimmed.isEmpty ? "video" : trimmed) + "-" + stamp
 }

 // What Google is asked about the video. It can hear it, so the words spoken are part of the answer.
 static let question = "This is a short social video someone saved as a reference. Describe it for a founder who cannot watch it, in plain words: (1) what happens, scene by scene with rough times; (2) every word spoken or sung, as close to exact as you can, and say clearly if there is no speech; (3) any text shown on screen; (4) the look: colors, style, camera, editing speed, and any music or sound effects; (5) the hook in the first three seconds and why it might keep people watching. Say what you could not tell. Describe only what is really in the video."
}
