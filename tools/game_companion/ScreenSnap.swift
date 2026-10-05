import AppKit
import CoreGraphics
import ScreenCaptureKit

// One picture of ALL the screens, side by side, laid out the way the screens sit on the desk (Matthew's choice, 2026-10-05: she sees
// every screen while she is live). Everything visible on every screen is in this picture and goes to Google while Friday is live.
// The arithmetic (layout, where a named spot lands on the desk) is in HandsData.swift and is tested.
enum ScreenSnap {
 struct Shot {
  var jpeg: Data
  var preview: NSImage
  var desk: CGRect          // the area of the desk the picture covers, in screen points (top-left origin)
 }

 // `maxWidth` x `maxHeight` is the size the whole picture is shrunk to fit. Needs the Screen Recording permission, like the window picker.
 static func captureAll(maxWidth: Double = 1600,maxHeight: Double = 900) async throws -> Shot {
  let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
  let displays = content.displays
  guard let plan = HandsPlan.layout(displays.map { $0.frame },maxWidth:maxWidth,maxHeight:maxHeight) else {
   throw NSError(domain:"ScreenSnap",code:1,userInfo:[NSLocalizedDescriptionKey:"No screens found."])
  }
  guard let space = CGColorSpace(name:CGColorSpace.sRGB),
        let canvas = CGContext(data:nil,width:plan.width,height:plan.height,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
   throw NSError(domain:"ScreenSnap",code:2,userInfo:[NSLocalizedDescriptionKey:"Couldn't make the picture."])
  }
  canvas.setFillColor(CGColor(red:0,green:0,blue:0,alpha:1))
  canvas.fill(CGRect(x:0,y:0,width:plan.width,height:plan.height))
  for display in displays {
   let target = HandsPlan.canvasRect(for:display.frame,union:plan.union,scale:plan.scale,canvasHeight:plan.height)
   let config = SCStreamConfiguration()
   config.width = max(1,Int(target.width.rounded()))
   config.height = max(1,Int(target.height.rounded()))
   config.showsCursor = true
   config.capturesAudio = false
   let filter = SCContentFilter(display:display,excludingWindows:[])
   let image = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
   canvas.draw(image,in:target)
  }
  guard let whole = canvas.makeImage(),
        let jpeg = NSBitmapImageRep(cgImage:whole).representation(using:.jpeg,properties:[.compressionFactor:0.6]) else {
   throw NSError(domain:"ScreenSnap",code:3,userInfo:[NSLocalizedDescriptionKey:"Couldn't encode the picture."])
  }
  let previewHeight = 240.0 * Double(plan.height) / Double(plan.width)
  return Shot(jpeg:jpeg,preview:NSImage(cgImage:whole,size:NSSize(width:240,height:previewHeight)),desk:plan.union)
 }
}
