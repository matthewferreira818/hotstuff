import SwiftUI

// The look in one place (revamp, 2026-10-24). Nothing uses this yet: the pages still use Noir and HubColor, and move over one page at a time,
// so adding it changes nothing on screen. Midnight is the default; Pure black is the High contrast switch (UserDefaults "hub.highContrast",
// to be set from Settings). Every text colour below is at least 4.5:1 against the surface it is meant for (measured on 2026-10-24).
enum HubTheme {
 static var highContrast: Bool { UserDefaults.standard.bool(forKey:"hub.highContrast") }

 static func hex(_ value: UInt32,_ opacity: Double = 1) -> Color {
  Color(red:Double((value >> 16) & 0xFF) / 255,green:Double((value >> 8) & 0xFF) / 255,blue:Double(value & 0xFF) / 255).opacity(opacity)
 }

 // Surfaces: layered blacks instead of shadows.
 static var background: Color { hex(highContrast ? 0x000000 : 0x050507) }
 static var sidebar: Color { hex(highContrast ? 0x000000 : 0x08080C) }
 static var card: Color { hex(highContrast ? 0x0A0A0C : 0x0D0D13) }
 static var line: Color { hex(highContrast ? 0x33333C : 0x23232D) }
 // Controls: black with a visible outline (white in High contrast).
 static var control: Color { hex(0x000000) }
 static var controlOutline: Color { hex(highContrast ? 0xFFFFFF : 0x4A4A5C) }

 // Text: off-white by default (pure white on pure black glares), pure white in High contrast.
 static var text: Color { hex(highContrast ? 0xFFFFFF : 0xF2F2F5) }
 static var subtext: Color { hex(highContrast ? 0xB4B4C0 : 0xA9A9B8) }   // 8.4:1 on the card (Midnight), 9.6:1 (High contrast)

 // Small highlights only. Never the only signal: every status also has a word or an icon.
 static let crimson = hex(0xD94A63)
 static let blue = hex(0x4D8DFF)
 static let green = hex(0x4ADE80)
 static let amber = hex(0xF5B544)

 // Orbs, one per member of the crew.
 static let orbClaude = amber
 static let orbRoxy = blue
 static let orbFriday = crimson

 // Spacing, shape and type sizes (points). Click targets are at least 44 high.
 static let pagePadding: CGFloat = 32
 static let cardPadding: CGFloat = 18
 static let cardRadius: CGFloat = 20
 static let gap: CGFloat = 14
 static let minTarget: CGFloat = 44
 static let titleSize: CGFloat = 28
 static let headingSize: CGFloat = 15
 static let bodySize: CGFloat = 14
 static let smallSize: CGFloat = 12.5
}
