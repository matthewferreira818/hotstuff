import AVFoundation
import CoreImage
import Cocoa

// Cleans up a downloaded Twitch clip on the Mac, for free and with nothing to install (Apple's own video tools).
//  1. Measures how loud the clip is moment to moment.
//  2. ClipMath picks the highlight: the loudest stretch, with the quiet before and after cut off.
//  3. Saves two files: the highlight as a normal wide video, and a tall 9:16 version (the game centered over a blurred copy
//     of itself) for TikTok, Reels and Shorts.
// It only reads the downloaded file and writes new files next to it. It never posts anything: Matthew does that himself.

struct ClipFiles {
 var original: URL
 var landscape: URL?
 var vertical: URL?
 var cut: ClipCut
 var note = ""
}

enum ClipEditError: LocalizedError {
 case noExporter
 var errorDescription: String? { "This Mac couldn't start its video exporter." }
}

enum ClipEditor {
 static let hop = 0.25

 // How loud each quarter second is, 0 to 1. Empty if the clip has no sound that can be read.
 static func loudness(of url: URL) async -> [Float] {
  let asset = AVURLAsset(url:url)
  guard let tracks = try? await asset.loadTracks(withMediaType:.audio), let track = tracks.first,
        let reader = try? AVAssetReader(asset:asset) else { return [] }
  let settings: [String:Any] = [
   AVFormatIDKey: Int(kAudioFormatLinearPCM),
   AVLinearPCMBitDepthKey: 16,
   AVLinearPCMIsFloatKey: false,
   AVLinearPCMIsBigEndianKey: false,
   AVLinearPCMIsNonInterleaved: false,
   AVSampleRateKey: 16000,
   AVNumberOfChannelsKey: 1
  ]
  let output = AVAssetReaderTrackOutput(track:track,outputSettings:settings)
  guard reader.canAdd(output) else { return [] }
  reader.add(output)
  guard reader.startReading() else { return [] }
  let perSlice = Int(16000 * hop)
  var levels: [Float] = []
  var sum = 0.0
  var count = 0
  while let buffer = output.copyNextSampleBuffer() {
   guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
   let length = CMBlockBufferGetDataLength(block)
   guard length >= 2 else { continue }
   var samples = [Int16](repeating:0,count:length / 2)
   let status = samples.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:length,destination:$0.baseAddress!) }
   guard status == kCMBlockBufferNoErr else { continue }
   for sample in samples {
    let value = Double(sample) / 32768.0
    sum += value * value
    count += 1
    if count == perSlice {
     levels.append(Float((sum / Double(count)).squareRoot()))
     sum = 0
     count = 0
    }
   }
  }
  if count > perSlice / 2 { levels.append(Float((sum / Double(count)).squareRoot())) }
  return levels
 }

 // Makes <folder>/highlight-wide.mp4 and <folder>/highlight-tall.mp4 from <folder>/original.mp4.
 static func tidy(original: URL,folder: URL,maxLength: Double) async throws -> ClipFiles {
  let asset = AVURLAsset(url:original)
  let duration = try await asset.load(.duration).seconds
  let levels = await loudness(of:original)
  var cut = ClipMath.highlight(levels:levels,hop:hop,maxLength:maxLength) ?? ClipCut(start:max(0,duration - maxLength),end:duration)
  cut.end = min(cut.end,duration)
  cut.start = min(max(0,cut.start),max(0,cut.end - 1))
  var files = ClipFiles(original:original,cut:cut)
  if levels.isEmpty { files.note = "The clip's sound couldn't be read, so it kept the most recent \(Int(maxLength)) seconds. " }
  let wide = folder.appendingPathComponent("highlight-wide.mp4")
  let tall = folder.appendingPathComponent("highlight-tall.mp4")
  do { try await export(original,to:wide,cut:cut,tall:false); files.landscape = wide }
  catch { files.note += "The wide version failed: \(error.localizedDescription). " }
  do { try await export(original,to:tall,cut:cut,tall:true); files.vertical = tall }
  catch { files.note += "The tall version failed: \(error.localizedDescription). " }
  if files.landscape == nil && files.vertical == nil { throw NSError(domain:"clips",code:10,userInfo:[NSLocalizedDescriptionKey:files.note]) }
  return files
 }

 static func export(_ source: URL,to destination: URL,cut: ClipCut,tall: Bool) async throws {
  let asset = AVURLAsset(url:source)
  guard let session = AVAssetExportSession(asset:asset,presetName:AVAssetExportPresetHighestQuality) else { throw ClipEditError.noExporter }
  session.timeRange = CMTimeRange(start:CMTime(seconds:cut.start,preferredTimescale:600),duration:CMTime(seconds:cut.length,preferredTimescale:600))
  if tall { session.videoComposition = tallComposition(for:asset) }
  try? FileManager.default.removeItem(at:destination)
  try await session.export(to:destination,as:.mp4)
 }

 // 1080 x 1920: the video fitted to the full width in the middle, over a blurred, zoomed copy of itself that fills the frame.
 // (Apple has marked this older, simpler composition class deprecated but it still works, and the warning it causes is harmless.)
 static func tallComposition(for asset: AVAsset) -> AVVideoComposition {
  let size = CGSize(width:1080,height:1920)
  let composition = AVMutableVideoComposition(asset:asset,applyingCIFiltersWithHandler:{ request in
   let source = request.sourceImage
   let extent = source.extent
   let fill = max(size.width / extent.width,size.height / extent.height)
   var back = source.transformed(by:CGAffineTransform(scaleX:fill,y:fill))
   let backExtent = back.extent
   back = back.transformed(by:CGAffineTransform(translationX:(size.width - backExtent.width) / 2 - backExtent.origin.x,y:(size.height - backExtent.height) / 2 - backExtent.origin.y))
   let blurred = back.clampedToExtent().applyingGaussianBlur(sigma:40).cropped(to:CGRect(origin:.zero,size:size))
   let fit = size.width / extent.width
   var front = source.transformed(by:CGAffineTransform(scaleX:fit,y:fit))
   let frontExtent = front.extent
   front = front.transformed(by:CGAffineTransform(translationX:-frontExtent.origin.x,y:(size.height - frontExtent.height) / 2 - frontExtent.origin.y))
   request.finish(with:front.composited(over:blurred),context:nil)
  })
  composition.renderSize = size
  return composition
 }
}
