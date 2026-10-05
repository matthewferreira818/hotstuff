import SwiftUI

// Noir look for Game Companion: near-black background, one crimson accent, and Friday as the orb in the middle.
enum Noir {
 // A mellow crimson (softer and dustier than the first version): rosewood, not neon.
 static let crimson = Color(red:0.74,green:0.21,blue:0.31)
 static let crimsonLight = Color(red:0.91,green:0.48,blue:0.55)
 static let crimsonDeep = Color(red:0.37,green:0.10,blue:0.17)
 static let ink = Color(red:0.04,green:0.03,blue:0.05)
 static let smoke = Color(red:0.07,green:0.04,blue:0.06)
}

enum OrbState { case off, idle, listening, thinking, speaking }

// How Friday looks. The choice is saved on this Mac and shared by every place she appears.
enum FridayLook: String, CaseIterable, Identifiable {
 case orb, faces, robot, fire
 var id: String { rawValue }
 var title: String {
  switch self { case .orb: return "Red orb"; case .faces: return "Emoji faces"; case .robot: return "Robot"; case .fire: return "Fire" }
 }
 func emoji(for state: OrbState) -> String {
  switch self {
  case .orb: return ""
  case .faces:
   switch state { case .off: return "😴"; case .idle: return "🙂"; case .listening: return "👂"; case .thinking: return "🤔"; case .speaking: return "😄" }
  case .robot:
   switch state { case .off: return "💤"; case .thinking: return "💭"; default: return "🤖" }
  case .fire: return state == .off ? "💤" : "🔥"
  }
 }
}

@MainActor final class FridayAppearance: ObservableObject {
 static let shared = FridayAppearance()
 @Published var look: FridayLook { didSet { UserDefaults.standard.set(look.rawValue,forKey:"friday.appearance") } }
 // True while the pointer is over an orb, which brings the look picker fully into view.
 @Published var hovering = false
 init() { look = FridayLook(rawValue:UserDefaults.standard.string(forKey:"friday.appearance") ?? "") ?? .orb }
}

// How the orb moves, worked out one frame at a time. Every number that depends on what Friday is doing (how fast the light drifts,
// how bright the aura is, how far the edge wobbles, whether ripples and sparks show) EASES toward its goal instead of jumping, and
// every speed is added up over time instead of multiplied by the clock, so changing speed never makes the picture jump. The sound
// level has fast attack and slow release, like a meter, so swelling follows the voice smoothly. This is what makes going from
// asleep to idle to hearing you to thinking to speaking look like one continuous motion.
final class OrbDynamics: ObservableObject {
 struct Frame {
  var glow = 0.30
  var level = 0.0            // smoothed sound, 0 to 1
  var flowPhase = 0.0        // adds up: where the drifting light is
  var wobble = 0.010         // how far the edge moves, as a fraction of the radius
  var wobblePhase = 0.0
  var ripples = 0.0          // 0 to 1: how visible the ripples are
  var ripplePhase = 0.0
  var sparks = 0.15          // 0 to 1: how visible the orbiting lights are
  var breath = 0.012         // size of the slow breathing
 }

 private var last: Double?
 private var frame = Frame()
 private var flow = 0.25
 private var wobbleBase = 0.010
 private var wobbleSpeed = 0.55
 private var rippleSpeed = 0.3

 private func clamp(_ x: Double) -> Double { x.isFinite ? min(1,max(0,x)) : 0 }

 // Moves everything a little toward where it should be. `t` is the clock; a repeat call with the same `t` returns the same frame.
 func step(t: Double,state: OrbState,level raw: Double,moves: Bool) -> Frame {
  guard moves else {
   // Reduce Motion: nothing moves, nothing pulses. The picture is the calm resting one.
   return Frame(glow:0.5,level:0,flowPhase:0,wobble:0,wobblePhase:0,ripples:0,ripplePhase:0,sparks:0.3,breath:0)
  }
  guard let previous = last else { last = t; return frame }
  let dt = min(max(t - previous,0),0.1)   // a long gap (window hidden) must not make a jump
  if dt <= 0 { return frame }
  last = t

  var glowGoal = 0.55, flowGoal = 0.8, wobbleGoal = 0.018, speedGoal = 0.8, rippleGoal = 0.0, sparkGoal = 0.50, breathGoal = 0.016
  let sounding = state == .listening || state == .speaking
  switch state {
  case .off: glowGoal = 0.30; flowGoal = 0.25; wobbleGoal = 0.010; speedGoal = 0.55; sparkGoal = 0.15; breathGoal = 0.012
  case .idle: break
  case .listening: glowGoal = 0.70; flowGoal = 1.2; wobbleGoal = 0.026; speedGoal = 1.2; rippleGoal = 1; sparkGoal = 0.75
  case .thinking: glowGoal = 0.66; flowGoal = 1.9; wobbleGoal = 0.034; speedGoal = 1.8; sparkGoal = 0.80
  case .speaking: glowGoal = 0.84; flowGoal = 1.6; wobbleGoal = 0.030; speedGoal = 1.5; rippleGoal = 1; sparkGoal = 0.75
  }

  // exponential easing: after `tau` seconds it has covered about two thirds of the way
  func ease(_ value: inout Double,to goal: Double,tau: Double) { value += (goal - value) * (1 - exp(-dt / tau)) }

  ease(&frame.glow,to:glowGoal,tau:0.8)
  ease(&flow,to:flowGoal,tau:0.9)
  ease(&wobbleBase,to:wobbleGoal,tau:0.8)
  ease(&wobbleSpeed,to:speedGoal,tau:0.9)
  ease(&frame.ripples,to:rippleGoal,tau:0.6)
  ease(&rippleSpeed,to:state == .speaking ? 0.55 : 0.35,tau:0.9)
  ease(&frame.sparks,to:min(1,sparkGoal + (sounding ? frame.level * 0.25 : 0)),tau:0.8)
  ease(&frame.breath,to:breathGoal,tau:0.9)

  // the meter: quick to rise with the voice, slow to fall when it stops
  let wanted = sounding ? clamp(raw) : 0
  ease(&frame.level,to:wanted,tau:wanted > frame.level ? 0.07 : 0.40)

  frame.flowPhase += dt * flow
  frame.wobblePhase += dt * wobbleSpeed
  frame.ripplePhase += dt * rippleSpeed
  frame.wobble = wobbleBase + frame.level * 0.07
  return frame
 }
}

// Friday as a glowing orb: a wide aura that fades smoothly into whatever is behind it (no hard edges, no dark ring), a liquid sphere of
// drifting light with a soft core that pulses with sound, a slowly turning glass rim, ripples while she talks or listens, and a few
// sparks orbiting. It only draws. The caller passes the state, the clock (`t`) and how loud the sound is (`level`, 0 to 1); OrbDynamics
// turns those into smooth motion.
struct FridayOrb: View {
 var state: OrbState
 var t: Double
 var level: Double = 0
 var size: CGFloat = 230
 var animated = true
 // The small look picker under the orb. Hidden where the orb is tiny; shown only when the pointer is over the orb.
 var showsPicker = true
 @ObservedObject private var appearance = FridayAppearance.shared
 @StateObject private var dynamics = OrbDynamics()
 @Environment(\.accessibilityReduceMotion) private var reduceMotion

 private var moves: Bool { animated && !reduceMotion }

 var body: some View {
  let m = dynamics.step(t:t,state:state,level:level,moves:moves)
  let time = moves ? t : 0
  ZStack {
   aura(m,time)
   if appearance.look == .orb {
    sphere(m,time)
     .scaleEffect(1 + sin(time * 1.0) * m.breath + m.level * 0.10)
     .opacity(0.72 + 0.28 * min(1,m.glow / 0.55))
   } else {
    bubble(m,time)
     .scaleEffect(1 + m.level * 0.08)
     .opacity(0.7 + 0.3 * min(1,m.glow / 0.55))
   }
   sparks(m,time)
  }
  .frame(width:size * 1.7,height:size * 1.45)
  .contentShape(Rectangle())
  .onHover { inside in appearance.hovering = inside }
  .overlay(alignment:.bottom) {
   if showsPicker {
    FridayLookDock()
     .opacity(appearance.hovering ? 1 : 0)
     .scaleEffect(appearance.hovering ? 1 : 0.94)
     .animation(.spring(response:0.45,dampingFraction:0.85),value:appearance.hovering)
     .padding(.bottom,2)
   }
  }
 }

 // The aura. Every gradient ends in the same colour at zero strength, never plain clear, so the fade has no grey or black fringe,
 // and none of it is blurred inside a box, so nothing is cut off at an edge.
 private func aura(_ m: OrbDynamics.Frame,_ time: Double) -> some View {
  let breath = 0.5 + 0.5 * sin(time * 0.9)
  let strength = m.glow * (0.85 + 0.15 * breath) + m.level * 0.28
  let violet = Color(red:0.50,green:0.30,blue:0.72)
  return ZStack {
   Circle().fill(RadialGradient(colors:[Noir.crimson.opacity(min(0.70,0.58 * strength)),Noir.crimson.opacity(0.20 * strength),Noir.crimson.opacity(0)],center:.center,startRadius:size * 0.28,endRadius:size * 1.12))
    .frame(width:size * 2.3,height:size * 2.3)
    .scaleEffect(1 + 0.035 * breath + m.level * 0.12)
   Circle().fill(RadialGradient(colors:[violet.opacity(0.26 * m.glow),violet.opacity(0)],center:.center,startRadius:0,endRadius:size * 0.85))
    .frame(width:size * 1.7,height:size * 1.7)
    .offset(x:cos(time * 0.33) * size * 0.16,y:sin(time * 0.27) * size * 0.12)
   Circle().stroke(Noir.crimsonLight.opacity(0.26 * m.glow + m.level * 0.30),lineWidth:size * 0.03)
    .frame(width:size,height:size)
    .blur(radius:size * 0.05)
   if m.ripples > 0.01 {
    ForEach(0..<3,id:\.self) { i in ripple(i,m) }
   }
  }
 }

 private func ripple(_ i: Int,_ m: OrbDynamics.Frame) -> some View {
  let phase = (m.ripplePhase + Double(i) / 3).truncatingRemainder(dividingBy:1)
  return Circle()
   .stroke(Noir.crimsonLight.opacity((1 - phase) * 0.28 * m.ripples),lineWidth:1.6)
   .frame(width:size,height:size)
   .scaleEffect(1 + phase * 0.6)
 }

 // The sphere: warm body, drifting light, liquid streaks, a soft core, a soft inner shade (crimson, never black) and a glass rim.
 private func sphere(_ m: OrbDynamics.Frame,_ time: Double) -> some View {
  ZStack {
   Circle().fill(RadialGradient(colors:[Color(red:0.80,green:0.46,blue:0.52),Noir.crimson,Noir.crimsonDeep],center:UnitPoint(x:0.36,y:0.30),startRadius:0,endRadius:size * 0.80))
   ForEach(0..<5,id:\.self) { i in blob(i,m) }
   ForEach(0..<2,id:\.self) { i in streak(i,m) }
   Circle().fill(RadialGradient(colors:[Color(red:1.0,green:0.84,blue:0.86).opacity(0.22 + m.level * 0.28),Noir.crimsonLight.opacity(0)],center:.center,startRadius:0,endRadius:size * (0.17 + m.level * 0.12)))
    .blendMode(.plusLighter)
   Circle().fill(RadialGradient(colors:[Noir.crimsonDeep.opacity(0),Noir.crimsonDeep.opacity(0.50)],center:.center,startRadius:size * 0.30,endRadius:size * 0.50))
   highlight
  }
  .frame(width:size,height:size)
  .clipShape(FridayBlob(phase:m.wobblePhase,amount:m.wobble))
  .overlay(rim(m,time))
  .drawingGroup()
 }

 private func rim(_ m: OrbDynamics.Frame,_ time: Double) -> some View {
  FridayBlob(phase:m.wobblePhase,amount:m.wobble).stroke(AngularGradient(colors:[Color.white.opacity(0.36),Noir.crimsonLight.opacity(0.10),Color.white.opacity(0.04),Noir.crimsonLight.opacity(0.40),Color.white.opacity(0.36)],center:.center,angle:.degrees(time * 16)),lineWidth:1.3)
 }

 // Five blurred patches of light wandering inside the sphere. Louder sound lets them roam further.
 private func blob(_ i: Int,_ m: OrbDynamics.Frame) -> some View {
  let angle = m.flowPhase * (0.55 + 0.17 * Double(i)) + Double(i) * 1.9
  let reach = size * (0.15 + 0.05 * Double(i % 2)) * (1 + m.level * 0.9)
  let palette: [Color] = [Noir.crimsonLight,Color(red:0.95,green:0.67,blue:0.58),Color(red:0.86,green:0.42,blue:0.62),Noir.crimson,Color(red:0.66,green:0.25,blue:0.46)]
  return Circle()
   .fill(palette[i])
   .frame(width:size * 0.60,height:size * 0.60)
   .blur(radius:size * 0.14)
   .offset(x:cos(angle) * reach * 1.5,y:sin(angle * 1.31) * reach * 1.3)
   .blendMode(.plusLighter)
   .opacity(i == 3 ? 0.36 : 0.46)
 }

 // Two soft bright streaks that turn slowly through the sphere, like light moving in liquid.
 private func streak(_ i: Int,_ m: OrbDynamics.Frame) -> some View {
  let turn = m.flowPhase * (0.35 + 0.2 * Double(i)) * 57.2958 + Double(i) * 70
  return Ellipse()
   .fill(LinearGradient(colors:[Noir.crimsonLight.opacity(0),Color.white.opacity(0.15),Noir.crimsonLight.opacity(0)],startPoint:.leading,endPoint:.trailing))
   .frame(width:size * 1.15,height:size * 0.26)
   .rotationEffect(.degrees(turn))
   .blur(radius:size * 0.045)
   .blendMode(.plusLighter)
 }

 private var highlight: some View {
  Ellipse()
   .fill(LinearGradient(colors:[Color.white.opacity(0.24),Color.white.opacity(0)],startPoint:.top,endPoint:.bottom))
   .frame(width:size * 0.44,height:size * 0.20)
   .blur(radius:size * 0.03)
   .offset(x:-size * 0.13,y:-size * 0.29)
 }

 // A dozen tiny lights orbiting on slightly different paths. Calm when she is idle, brighter when she talks.
 private func sparks(_ m: OrbDynamics.Frame,_ time: Double) -> some View {
  ZStack {
   ForEach(0..<12,id:\.self) { i in
    let angle = time * (0.10 + 0.012 * Double(i % 5)) + Double(i) * 0.5236 + sin(time * 0.3 + Double(i)) * 0.2
    let radius = size * (0.60 + 0.06 * Double(i % 4))
    let twinkle = 0.5 + 0.5 * sin(time * 1.7 + Double(i) * 1.3)
    Circle().fill(Color.white)
     .frame(width:size * 0.016 * CGFloat(1 + i % 3),height:size * 0.016 * CGFloat(1 + i % 3))
     .shadow(color:Noir.crimsonLight,radius:size * 0.025)
     .offset(x:cos(angle) * radius * 1.18,y:sin(angle) * radius * 0.80)
     .opacity((0.25 + 0.6 * twinkle) * m.sparks)
   }
  }
 }

 // The emoji looks: the same aura, with the emoji in a glass bubble that bobs, tilts and bounces with sound.
 private func bubble(_ m: OrbDynamics.Frame,_ time: Double) -> some View {
  ZStack {
   Circle().fill(RadialGradient(colors:[Noir.crimson.opacity(0.34),Noir.crimsonDeep.opacity(0.14)],center:UnitPoint(x:0.4,y:0.3),startRadius:0,endRadius:size * 0.6))
   Circle().strokeBorder(AngularGradient(colors:[Color.white.opacity(0.55),Noir.crimsonLight.opacity(0.10),Color.white.opacity(0.05),Noir.crimsonLight.opacity(0.45),Color.white.opacity(0.55)],center:.center,angle:.degrees(time * 14)),lineWidth:1.5 + m.level * 2)
   Text(appearance.look.emoji(for:state))
    .font(.system(size:size * 0.50))
    .rotationEffect(.degrees(moves && state == .thinking ? sin(time * 2.2) * 7 : 0))
    .offset(y:moves ? (state == .speaking ? -m.level * size * 0.05 : sin(time * 1.2) * size * 0.012) : 0)
  }
  .frame(width:size * 0.9,height:size * 0.9)
 }
}

// The orb's edge: a circle whose outline slowly wobbles, the way an assistant's voice orb breathes and swells. `amount` is how far it
// moves as a fraction of the radius; the biggest bulge still stays inside the orb's frame.
struct FridayBlob: Shape {
 var phase: Double
 var amount: Double

 func path(in rect: CGRect) -> Path {
  let centre = CGPoint(x:rect.midX,y:rect.midY)
  let radius = Double(min(rect.width,rect.height)) / 2
  let base = radius * (1 - 1.3 * amount)
  let steps = 96
  var path = Path()
  for i in 0...steps {
   let angle = Double(i) / Double(steps) * 2 * Double.pi
   let wobble = sin(angle * 3 + phase * 1.1) * 0.55 + sin(angle * 5 - phase * 0.8) * 0.30 + sin(angle * 2 + phase * 0.6) * 0.45
   let r = base * (1 + amount * wobble)
   let point = CGPoint(x:centre.x + CGFloat(cos(angle) * r),y:centre.y + CGFloat(sin(angle) * r))
   if i == 0 { path.move(to:point) } else { path.addLine(to:point) }
  }
  path.closeSubpath()
  return path
 }
}

// The look picker: a small glass pill with one round button per look. The chosen one glows crimson and slides between choices.
struct FridayLookDock: View {
 @ObservedObject private var appearance = FridayAppearance.shared
 @Namespace private var pick

 var body: some View {
  HStack(spacing:4) {
   ForEach(FridayLook.allCases) { look in
    Button {
     withAnimation(.spring(response:0.4,dampingFraction:0.72)) { appearance.look = look }
    } label: {
     glyph(look)
      .frame(width:34,height:30)
      .background {
       if appearance.look == look {
        Capsule()
         .fill(LinearGradient(colors:[Noir.crimsonLight,Noir.crimson],startPoint:.topLeading,endPoint:.bottomTrailing))
         .matchedGeometryEffect(id:"look",in:pick)
         .shadow(color:Noir.crimson.opacity(0.55),radius:7)
       }
      }
    }
    .buttonStyle(.plain)
    .help(look.title)
   }
  }
  .padding(4)
  .background(.ultraThinMaterial,in:Capsule())
  .overlay(Capsule().strokeBorder(LinearGradient(colors:[Color.white.opacity(0.32),Color.white.opacity(0.06)],startPoint:.top,endPoint:.bottom),lineWidth:1))
  .shadow(color:Color.black.opacity(0.30),radius:10,y:5)
 }

 @ViewBuilder private func glyph(_ look: FridayLook) -> some View {
  switch look {
  case .orb:
   Circle().fill(RadialGradient(colors:[Color(red:0.95,green:0.67,blue:0.68),Noir.crimson,Noir.crimsonDeep],center:UnitPoint(x:0.35,y:0.30),startRadius:0,endRadius:14)).frame(width:18,height:18)
  case .faces: Text("😊").font(.system(size:17))
  case .robot: Text("🤖").font(.system(size:17))
  case .fire: Text("🔥").font(.system(size:17))
  }
 }
}

// A soft charcoal-and-plum gradient with slow drifting glows, so the edges are never black.
struct NoirBackground: View {
 @Environment(\.accessibilityReduceMotion) private var reduceMotion

 var body: some View {
  TimelineView(.animation(minimumInterval:1.0/20.0,paused:reduceMotion)) { timeline in
   let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
   GeometryReader { geo in
    let reach = max(geo.size.width,geo.size.height)
    ZStack {
     LinearGradient(colors:[Color(red:0.11,green:0.08,blue:0.11),Color(red:0.06,green:0.05,blue:0.09)],startPoint:.topLeading,endPoint:.bottomTrailing)
     glow(Noir.crimson.opacity(0.16),x:0.16 + 0.05 * sin(t * 0.11),y:0.10 + 0.05 * cos(t * 0.09),radius:reach * 0.75)
     glow(Color(red:0.38,green:0.24,blue:0.60).opacity(0.12),x:0.86 + 0.05 * cos(t * 0.08),y:0.90 + 0.04 * sin(t * 0.10),radius:reach * 0.70)
     glow(Noir.crimsonDeep.opacity(0.22),x:0.55 + 0.06 * sin(t * 0.07),y:0.50 + 0.06 * cos(t * 0.06),radius:reach * 0.55)
    }
   }
  }
  .ignoresSafeArea()
 }

 private func glow(_ color: Color,x: Double,y: Double,radius: CGFloat) -> some View {
  RadialGradient(colors:[color,Color.clear],center:UnitPoint(x:x,y:y),startRadius:0,endRadius:radius)
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
   .background(Circle().fill(filled ? AnyShapeStyle(LinearGradient(colors:[Noir.crimsonLight.opacity(0.85),Noir.crimson],startPoint:.top,endPoint:.bottom)) : AnyShapeStyle(Color.white.opacity(0.07))))
   .overlay(Circle().stroke(filled ? Color.white.opacity(0.22) : Color.white.opacity(0.10),lineWidth:1))
   .shadow(color:filled ? Noir.crimson.opacity(0.35) : Color.clear,radius:16,y:4)
   .scaleEffect(configuration.isPressed ? 0.92 : 1)
   .opacity(configuration.isPressed ? 0.85 : 1)
   .animation(.spring(response:0.28,dampingFraction:0.6),value:configuration.isPressed)
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
