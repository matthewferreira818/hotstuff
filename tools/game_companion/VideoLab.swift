import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

// The Video lab: turns a video file on Matthew's Mac into something Claude can actually study.
// Matthew's ask (2026-10-13): "we need to find a way for you to analyze videos". Claude, in the chat, can read pictures and words but cannot play a
// video, so the lab makes both: CONTACT SHEETS (a grid of frames, each stamped with its time, small enough to paste into the chat) and a WRITTEN
// PLAY-BY-PLAY from Google's reader, which can hear as well as see (so the words spoken in the video come through). The rules and the maths are in
// VideoLabData.swift (tested).
// What stays on the Mac: the pictures and the sheets (folder "Video Lab" inside the clips folder). What leaves the Mac: only the "words" step, which
// sends a small shrunken copy of the video to Google with Matthew's own free key (Google's free tier may use it to improve its products). Nothing is
// posted anywhere. It is meant for his own recordings and for videos he saved as a reference.
// Checked against Apple's docs on 2026-10-13: AVAssetImageGenerator.image(at:) async, appliesPreferredTrackTransform, maximumSize;
// AVAsset.load(.duration), loadTracks(withMediaType:), AVAssetTrack.load(.naturalSize/.preferredTransform);
// NSImage(size:flipped:drawingHandler:), NSBitmapImageRep.representation(using:properties:), NSOpenPanel.allowedContentTypes.

@MainActor final class VideoLab: ObservableObject {
 @Published var working = false
 @Published var status = ""
 @Published var notice = ""   // the amber line: why the play-by-play is missing or only covers the sound
 @Published var words = ""
 @Published var sheets: [URL] = []
 @Published var videoName = ""
 private var reader: VoiceOver?
 private(set) var folder: URL?

 static var root: URL { TwitchClips.clipsRoot.appendingPathComponent("Video Lab",isDirectory:true) }

 func attach(_ voice: VoiceOver) { reader = voice }

 func choose() {
  let panel = NSOpenPanel()
  panel.title = "Choose a video"
  panel.message = "A screen recording, or a TikTok you saved. It stays on your Mac."
  panel.canChooseFiles = true
  panel.canChooseDirectories = false
  panel.allowsMultipleSelection = false
  panel.allowedContentTypes = [.movie]
  guard panel.runModal() == .OK, let url = panel.url else { return }
  Task { await analyze(url) }
 }

 func analyze(_ url: URL) async {
  if working { return }
  working = true
  defer { working = false }
  words = ""
  notice = ""
  sheets = []
  videoName = url.lastPathComponent
  status = "Opening the video…"
  let asset = AVURLAsset(url:url)
  let duration: Double
  let aspect: Double
  do {
   duration = try await asset.load(.duration).seconds
   guard let track = try await asset.loadTracks(withMediaType:.video).first else { status = "That file has no picture in it, so there is nothing to look at."; return }
   let natural = try await track.load(.naturalSize)
   let transform = try await track.load(.preferredTransform)
   let shown = natural.applying(transform)
   aspect = abs(shown.height) > 0 ? Double(abs(shown.width) / abs(shown.height)) : 16.0 / 9.0
  } catch {
   status = "I couldn't open that video: \(error.localizedDescription)"
   return
  }
  let count = VideoLabPlan.frameCount(duration:duration)
  guard count > 0, let plan = VideoLabPlan.layout(count:min(count,VideoLabPlan.perSheet(VideoLabPlan.shape(aspect:aspect))),aspect:aspect) else { status = "That video has no length I can read."; return }
  let times = VideoLabPlan.frameTimes(duration:duration,count:count)
  let generator = AVAssetImageGenerator(asset:asset)
  generator.appliesPreferredTrackTransform = true
  generator.maximumSize = CGSize(width:CGFloat(plan.tileWidth) * 1.5,height:CGFloat(plan.tileHeight) * 1.5)
  generator.requestedTimeToleranceBefore = CMTime(seconds:0.4,preferredTimescale:600)
  generator.requestedTimeToleranceAfter = CMTime(seconds:0.4,preferredTimescale:600)
  var frames: [(time: Double,image: CGImage)] = []
  for (index,time) in times.enumerated() {
   status = "Taking pictures… \(index + 1) of \(times.count)"
   if let made = try? await generator.image(at:CMTime(seconds:time,preferredTimescale:600)) { frames.append((time,made.image)) }
  }
  guard frames.count >= 2 else { status = "I could only get \(frames.count) picture from that video, so there is no sheet to make."; return }
  // The folder for this video: Movies / Game Companion Clips / Video Lab / name-date
  let stamp = DateFormatter()
  stamp.dateFormat = "yyyyMMdd-HHmmss"
  let target = Self.root.appendingPathComponent(VideoLabPlan.folderName(for:url.lastPathComponent,stamp:stamp.string(from:Date())),isDirectory:true)
  do { try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true) } catch { status = "I couldn't make a folder for the sheets: \(error.localizedDescription)"; return }
  folder = target
  status = "Laying out the contact sheets…"
  var made: [URL] = []
  let ranges = VideoLabPlan.sheetRanges(total:frames.count,aspect:aspect)
  for (number,range) in ranges.enumerated() {
   let part = Array(frames[range])
   guard let layout = VideoLabPlan.layout(count:part.count,aspect:aspect) else { continue }
   let title = "\(url.lastPathComponent)  ·  sheet \(number + 1) of \(ranges.count)  ·  \(VideoLabPlan.label(duration)) long"
   let image = Self.sheetImage(part,layout:layout,title:title)
   guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data:tiff),
         let jpeg = rep.representation(using:.jpeg,properties:[.compressionFactor:0.8]) else { continue }
   let file = target.appendingPathComponent("sheet-\(number + 1).jpg")
   if (try? jpeg.write(to:file)) != nil { made.append(file) }
  }
  sheets = made
  guard !made.isEmpty else { status = "I took the pictures but couldn't save the sheets."; return }
  copySheet(1)
  let left = frames.count - (ranges.last?.upperBound ?? 0)
  var report = "\(made.count) contact sheet\(made.count == 1 ? "" : "s") ready (\(frames.count) pictures, each stamped with its time). Sheet 1 is on your clipboard: paste it into the chat with Claude."
  if left > 0 { report += " (\(left) later pictures didn't fit on the sheets.)" }
  // The words: Google watches and listens to a small copy.
  let mode = VideoLabPlan.wordsMode(duration:duration)
  if mode == .none {
   status = report
   notice = "No play-by-play: the video is longer than \(Int(VideoLabPlan.maxAudioSeconds / 60)) minutes, which is too long to send to Google. The sheets are ready."
   return
  }
  guard let voice = reader else {
   status = report
   notice = "No play-by-play: the helper that talks to Google isn't connected. Quit and reopen Friday, then choose the video again."
   return
  }
  status = report + (mode == .video ? " Now Google is watching and listening… (a minute or two)" : " Now Google is listening… (a minute or two)")
  let result = await voice.readVideoFile(url,question:VideoLabPlan.question,audioQuestion:VideoLabPlan.audioQuestion,audioOnly:mode == .audioOnly)
  if let text = result.text {
   // The note goes at the top of the words, so it travels with them when they are pasted into the chat.
   words = (result.note.map { "[\($0)]\n\n" } ?? "") + text
   try? words.write(to:target.appendingPathComponent("play-by-play.txt"),atomically:true,encoding:.utf8)
   status = report + " The play-by-play is below; the copy button puts it on your clipboard too."
   notice = result.note ?? ""
  } else {
   status = report
   notice = "The play-by-play didn't work: \(result.problem ?? "no answer")."
  }
 }

 func copySheet(_ number: Int) {
  guard sheets.indices.contains(number - 1), let image = NSImage(contentsOf:sheets[number - 1]) else { return }
  let board = NSPasteboard.general
  board.clearContents()
  board.writeObjects([image])
 }

 // Every sheet at once, as separate pictures on the clipboard. Some chat boxes paste them all, some only the first; the single-sheet buttons always work.
 func copyAllSheets() {
  let images = sheets.compactMap { NSImage(contentsOf:$0) }
  guard !images.isEmpty else { return }
  let board = NSPasteboard.general
  board.clearContents()
  board.writeObjects(images)
 }

 func copyWords() {
  guard !words.isEmpty else { return }
  let board = NSPasteboard.general
  board.clearContents()
  board.setString(words,forType:.string)
 }

 func openFolder() {
  let target = folder ?? Self.root
  try? FileManager.default.createDirectory(at:target,withIntermediateDirectories:true)
  NSWorkspace.shared.open(target)
 }

 // One sheet: dark background, a title line across the top (video name, sheet number, length), and each picture with its time under it.
 private static func sheetImage(_ frames: [(time: Double,image: CGImage)],layout: VideoLabPlan.Layout,title: String) -> NSImage {
  let size = NSSize(width:VideoLabPlan.sheetWidth,height:layout.sheetHeight)
  return NSImage(size:size,flipped:true) { rect in
   NSColor(calibratedWhite:0.07,alpha:1).setFill()
   rect.fill()
   let stamp: [NSAttributedString.Key:Any] = [.font:NSFont.monospacedSystemFont(ofSize:22,weight:.bold),.foregroundColor:NSColor.white]
   for (index,frame) in frames.enumerated() {
    let col = index % layout.columns
    let row = index / layout.columns
    let x = VideoLabPlan.gap + col * (layout.tileWidth + VideoLabPlan.gap)
    let y = VideoLabPlan.headerHeight + VideoLabPlan.gap + row * (layout.tileHeight + VideoLabPlan.labelHeight + VideoLabPlan.gap)
    let tile = NSRect(x:x,y:y,width:layout.tileWidth,height:layout.tileHeight)
    // Fit the picture inside its tile without stretching it.
    let w = CGFloat(frame.image.width), h = CGFloat(frame.image.height)
    let scale = min(tile.width / max(1,w),tile.height / max(1,h))
    let fit = NSRect(x:tile.midX - w * scale / 2,y:tile.midY - h * scale / 2,width:w * scale,height:h * scale)
    NSImage(cgImage:frame.image,size:NSSize(width:w,height:h)).draw(in:fit,from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:nil)
    NSString(string:VideoLabPlan.label(frame.time)).draw(at:NSPoint(x:CGFloat(x) + 2,y:tile.maxY + 3),withAttributes:stamp)
   }
   NSString(string:title).draw(at:NSPoint(x:CGFloat(VideoLabPlan.gap),y:10),withAttributes:stamp)
   return true
  }
 }
}

extension CompanionInterfaceView {
 var hubStreamVideoLab: some View {
  VStack(alignment:.leading,spacing:12) {
   HStack(spacing:10) {
    Text("Video lab: let Claude see a video").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
    if lab.working { ProgressView().controlSize(.small) }
    Spacer()
   }
   Text("Claude can read pictures and words but can't play a video. Choose a video file and the lab makes contact sheets (a grid of pictures, each stamped with its time) and a written play-by-play from Google, which can hear the words too. Paste the sheet and the play-by-play into your chat with Claude and he can study it with you.").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.65))
   Text("For a TikTok: save it first (the Share button, then Save video, or on tiktok.com right-click the video and choose Download video when the creator allows it), then choose that file here. Only use videos that are yours or that you saved as a reference. Nothing is posted anywhere.").font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
   HStack(spacing:10) {
    Button { lab.choose() } label: { Label("Choose a video…",systemImage:"film") }.buttonStyle(PillButtonStyle()).disabled(lab.working)
    if lab.sheets.count > 1 {
     Button { lab.copyAllSheets() } label: { Label("Copy all \(lab.sheets.count) sheets",systemImage:"square.stack") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    }
    ForEach(Array(lab.sheets.enumerated()),id:\.offset) { item in
     Button { lab.copySheet(item.offset + 1) } label: { Label("Copy sheet \(item.offset + 1)",systemImage:"doc.on.clipboard") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    }
    if !lab.words.isEmpty {
     Button { lab.copyWords() } label: { Label("Copy the play-by-play",systemImage:"text.quote") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    }
    Button { lab.openFolder() } label: { Label("Open the folder",systemImage:"folder") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   }
   if !lab.status.isEmpty {
    Text(lab.status).font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.75)).textSelection(.enabled)
   }
   if !lab.notice.isEmpty {
    Text(lab.notice).font(.system(size:12.5,weight:.semibold,design:.rounded)).foregroundStyle(Color.orange).textSelection(.enabled)
   }
   if !lab.words.isEmpty {
    Text(lab.words).font(.system(size:12.5,design:.rounded)).foregroundStyle(Noir.crimsonLight).textSelection(.enabled)
   }
   Text("The pictures and sheets stay on this Mac. Only the play-by-play step sends a small shrunken copy of the video to Google, with your free Gemini key; Google's free tier may use it to improve its products. Google can get things wrong, and it can't tell you who is speaking.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.45))
  }
  .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
 }
}
