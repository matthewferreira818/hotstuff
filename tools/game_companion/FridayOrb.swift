import SwiftUI

// Noir look for Game Companion: near-black background, one crimson accent, and Friday as the orb in the middle.
enum Noir {
 static let crimson = Color(red:0.88,green:0.08,blue:0.24)
 static let crimsonLight = Color(red:1.0,green:0.30,blue:0.40)
 static let crimsonDeep = Color(red:0.50,green:0.03,blue:0.12)
 static let ink = Color(red:0.02,green:0.02,blue:0.03)
 static let smoke = Color(red:0.07,green:0.02,blue:0.04)
}

enum OrbState { case off, idle, listening, thinking, speaking }

// The orb only draws. The caller decides the state and passes the clock in `t`, so it stays easy to test.
struct FridayOrb: View {
 var state: OrbState
 var t: Double
 var size: CGFloat = 140
 var animated = true

 private var speed: Double {
  switch state { case .off: return 0.5; case .idle: return 1.0; case .listening: return 2.2; case .thinking: return 3.0; case .speaking: return 4.2 }
 }
 private var swing: Double {
  switch state { case .off: return 0.012; case .idle: return 0.03; case .listening: return 0.06; case .thinking: return 0.04; case .speaking: return 0.085 }
 }
 private var glow: Double {
  switch state { case .off: return 0.22; case .idle: return 0.5; case .listening: return 0.7; case .thinking: return 0.62; case .speaking: return 0.9 }
 }
 private var spin: Double {
  switch state { case .off: return 6; case .idle: return 12; case .listening: return 26; case .thinking: return 110; case .speaking: return 45 }
 }

 var body: some View {
  let time = animated ? t : 0
  let breath = sin(time * speed)
  ZStack {
   Circle().fill(Noir.crimson).frame(width:size,height:size).blur(radius:size*0.28)
    .opacity(glow * (0.8 + 0.2 * breath)).scaleEffect(1.25)
   if animated && (state == .listening || state == .speaking) {
    ForEach(0..<3,id:\.self) { i in ring(i,time) }
   }
   orbBody(time)
    .scaleEffect(1 + swing * breath)
    .opacity(state == .off ? 0.55 : 1)
  }
  .frame(width:size*1.9,height:size*1.5)
  .drawingGroup()
 }

 private func orbBody(_ time: Double) -> some View {
  Circle()
   .fill(RadialGradient(colors:[Noir.crimsonLight,Noir.crimson,Noir.crimsonDeep,Color.black],center:UnitPoint(x:0.38,y:0.3),startRadius:size*0.02,endRadius:size*0.62))
   .frame(width:size,height:size)
   .overlay(swirl(time))
   .overlay(Circle().stroke(Color.white.opacity(0.12),lineWidth:1))
   .overlay(highlight)
 }

 // A slow turning shine inside the orb. It turns faster while thinking.
 private func swirl(_ time: Double) -> some View {
  Circle()
   .fill(AngularGradient(colors:[Noir.crimsonLight.opacity(0.0),Noir.crimsonLight.opacity(0.55),Noir.crimsonLight.opacity(0.0),Color.black.opacity(0.35),Noir.crimsonLight.opacity(0.0)],center:.center))
   .frame(width:size*0.92,height:size*0.92)
   .blur(radius:size*0.07)
   .rotationEffect(.degrees(time * spin))
   .blendMode(.plusLighter)
 }

 private var highlight: some View {
  Ellipse()
   .fill(LinearGradient(colors:[Color.white.opacity(0.55),Color.white.opacity(0)],startPoint:.top,endPoint:.bottom))
   .frame(width:size*0.42,height:size*0.2)
   .blur(radius:size*0.03)
   .offset(x:-size*0.12,y:-size*0.28)
 }

 // Rings that spread outward while she is listening or speaking.
 private func ring(_ i: Int,_ time: Double) -> some View {
  let rate = state == .speaking ? 0.55 : 0.35
  let phase = (time * rate + Double(i) / 3).truncatingRemainder(dividingBy:1)
  return Circle()
   .stroke(Noir.crimsonLight.opacity((1 - phase) * 0.35),lineWidth:2)
   .frame(width:size,height:size)
   .scaleEffect(1 + phase * 0.55)
 }
}

struct NoirBackground: View {
 var body: some View {
  ZStack {
   LinearGradient(colors:[Noir.ink,Noir.smoke],startPoint:.top,endPoint:.bottom)
   RadialGradient(colors:[Noir.crimson.opacity(0.20),Color.clear],center:.top,startRadius:10,endRadius:430)
  }
  .ignoresSafeArea()
 }
}

// Dark glass cards with a thin light edge, used for every GroupBox in the app.
struct NoirCard: GroupBoxStyle {
 func makeBody(configuration: Configuration) -> some View {
  VStack(alignment:.leading,spacing:10) {
   configuration.label
   configuration.content
  }
  .padding(16)
  .background(RoundedRectangle(cornerRadius:18,style:.continuous).fill(Color.white.opacity(0.045)))
  .overlay(RoundedRectangle(cornerRadius:18,style:.continuous).stroke(Color.white.opacity(0.08),lineWidth:1))
 }
}
