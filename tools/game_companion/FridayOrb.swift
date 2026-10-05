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

// A soft glowing sphere with light that drifts around inside it, like a voice assistant's orb.
// It only draws. The caller passes the state, the clock (`t`) and how loud the sound is (`level`, 0 to 1).
struct FridayOrb: View {
 var state: OrbState
 var t: Double
 var level: Double = 0
 var size: CGFloat = 230
 var animated = true

 // How fast the light drifts inside the orb.
 private var flow: Double {
  switch state { case .off: return 0.35; case .idle: return 0.7; case .listening: return 1.1; case .thinking: return 2.2; case .speaking: return 1.6 }
 }
 private var speed: Double {
  switch state { case .off: return 0.5; case .idle: return 1.0; case .listening: return 1.6; case .thinking: return 2.4; case .speaking: return 2.2 }
 }
 private var swing: Double {
  switch state { case .off: return 0.01; case .idle: return 0.025; case .listening: return 0.03; case .thinking: return 0.035; case .speaking: return 0.04 }
 }
 private var glow: Double {
  switch state { case .off: return 0.22; case .idle: return 0.5; case .listening: return 0.62; case .thinking: return 0.6; case .speaking: return 0.78 }
 }

 var body: some View {
  let time = animated ? t : 0
  let breath = sin(time * speed)
  let swell = 1 + swing * breath + level * 0.12
  ZStack {
   Circle().fill(Noir.crimson).frame(width:size,height:size).blur(radius:size*0.26)
    .opacity(min(1,glow * (0.8 + 0.2 * breath) + level * 0.25)).scaleEffect(1.2 + level * 0.12)
   if animated && (state == .listening || state == .speaking) {
    ForEach(0..<3,id:\.self) { i in ring(i,time) }
   }
   sphere(time)
    .scaleEffect(swell)
    .opacity(state == .off ? 0.6 : 1)
  }
  .frame(width:size*1.7,height:size*1.45)
  .drawingGroup()
 }

 private func sphere(_ time: Double) -> some View {
  ZStack {
   Circle().fill(RadialGradient(colors:[Noir.crimsonDeep,Color.black],center:.center,startRadius:0,endRadius:size*0.6))
   ForEach(0..<4,id:\.self) { i in blob(i,time) }
   // A soft dark rim gives the sphere depth.
   Circle().fill(RadialGradient(colors:[Color.clear,Color.black.opacity(0.55)],center:.center,startRadius:size*0.30,endRadius:size*0.52))
   highlight
  }
  .frame(width:size,height:size)
  .clipShape(Circle())
  .overlay(Circle().stroke(Color.white.opacity(0.10),lineWidth:1))
 }

 // Four blurred patches of light that wander inside the sphere. Louder sound lets them roam further.
 private func blob(_ i: Int,_ time: Double) -> some View {
  let angle = time * flow * (0.55 + 0.17 * Double(i)) + Double(i) * 1.9
  let reach = size * (0.16 + 0.05 * Double(i % 2)) * (1 + level * 0.8)
  let colors: [Color] = [Noir.crimsonLight,Noir.crimson,Color(red:1.0,green:0.46,blue:0.52),Noir.crimsonDeep]
  return Circle()
   .fill(colors[i])
   .frame(width:size*0.62,height:size*0.62)
   .blur(radius:size*0.15)
   .offset(x:cos(angle) * reach * 1.5,y:sin(angle * 1.31) * reach * 1.3)
   .blendMode(.plusLighter)
   .opacity(i == 3 ? 0.5 : 0.78)
 }

 private var highlight: some View {
  Ellipse()
   .fill(LinearGradient(colors:[Color.white.opacity(0.45),Color.white.opacity(0)],startPoint:.top,endPoint:.bottom))
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
   RadialGradient(colors:[Noir.crimson.opacity(0.20),Color.clear],center:.center,startRadius:10,endRadius:430)
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

// The round buttons under the orb. `filled` paints one crimson.
struct OrbButtonStyle: ButtonStyle {
 var diameter: CGFloat = 56
 var filled = false
 func makeBody(configuration: Configuration) -> some View {
  configuration.label
   .font(.system(size:diameter * 0.36,weight:.semibold))
   .foregroundStyle(Color.white.opacity(filled ? 1 : 0.88))
   .frame(width:diameter,height:diameter)
   .background(Circle().fill(filled ? Noir.crimson : Color.white.opacity(0.08)))
   .overlay(Circle().stroke(filled ? Noir.crimsonLight.opacity(0.5) : Color.white.opacity(0.12),lineWidth:1))
   .scaleEffect(configuration.isPressed ? 0.94 : 1)
   .opacity(configuration.isPressed ? 0.85 : 1)
 }
}

extension View {
 // A plain dark text box with a thin edge. The blue focus ring is switched off at the window level.
 func noirField() -> some View {
  self.textFieldStyle(.plain)
   .padding(.horizontal,14)
   .padding(.vertical,11)
   .background(RoundedRectangle(cornerRadius:14,style:.continuous).fill(Color.white.opacity(0.06)))
   .overlay(RoundedRectangle(cornerRadius:14,style:.continuous).stroke(Color.white.opacity(0.10),lineWidth:1))
 }
}
