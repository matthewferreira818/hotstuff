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

// Appearance stays on this Mac. Keeping the picker here avoids changing the voice engines.
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
 @Published var look: FridayLook {
  didSet { UserDefaults.standard.set(look.rawValue,forKey:"friday.appearance") }
 }
 init() { look = FridayLook(rawValue:UserDefaults.standard.string(forKey:"friday.appearance") ?? "") ?? .orb }
}

// The caller supplies the current activity, clock and measured sound level (0...1).
// No microphone, network connection or speech starts from this view.
struct FridayOrb: View {
 var state: OrbState
 var t: Double
 var level: Double = 0
 var size: CGFloat = 230
 var animated = true
 @StateObject private var appearance = FridayAppearance()
 @Environment(\.accessibilityReduceMotion) private var reduceMotion

 private var moves: Bool { animated && !reduceMotion }
 private var sound: Double {
  guard moves, level.isFinite, state == .listening || state == .speaking else { return 0 }
  return min(1,max(0,level))
 }
 private var flow: Double {
  switch state { case .off: return 0; case .idle: return 0.28; case .listening: return 0.55; case .thinking: return 0.95; case .speaking: return 0.7 }
 }
 private var activity: String {
  switch state { case .off: return "Asleep"; case .idle: return "Ready"; case .listening: return "Listening"; case .thinking: return "Thinking"; case .speaking: return "Speaking" }
 }

 var body: some View {
  let time = moves ? t : 0
  let phase = time * flow
  let breath = moves && state != .off ? sin(time * 1.4) * 0.012 : 0
  let swell = 1 + breath + sound * 0.085
  ZStack {
   halo
   if appearance.look == .orb {
    fluid(phase).scaleEffect(swell).opacity(state == .off ? 0.45 : 1)
   } else {
    emoji(phase).scaleEffect(1 + sound * 0.10).opacity(state == .off ? 0.55 : 1)
   }
  }
  .frame(width:size*1.7,height:size*1.45)
  .overlay(alignment:.bottom) { appearanceMenu.padding(.bottom,4) }
 }

 private var halo: some View {
  Circle()
   .fill(RadialGradient(colors:[Noir.crimson.opacity(state == .off ? 0.12 : 0.28 + sound * 0.18),Noir.crimsonDeep.opacity(0.10),.clear],center:.center,startRadius:size*0.20,endRadius:size*0.69))
   .frame(width:size*1.4,height:size*1.4)
   .scaleEffect(1 + sound * 0.12)
   .accessibilityHidden(true)
 }

 private func fluid(_ phase: Double) -> some View {
  let contour = FridayContour(phase:phase,energy:sound)
  return ZStack {
   contour.fill(RadialGradient(colors:[Noir.crimsonLight,Noir.crimson,Noir.crimsonDeep],center:.topLeading,startRadius:0,endRadius:size*0.9))
   ZStack {
    ForEach(0..<5,id:\.self) { i in current(i,phase) }
    // A warm bright crest and shaded base give the moving colour depth.
    Ellipse()
     .fill(LinearGradient(colors:[Color(red:1,green:0.86,blue:0.84).opacity(0.85),Noir.crimsonLight.opacity(0.05)],startPoint:.topLeading,endPoint:.bottomTrailing))
     .frame(width:size*0.92,height:size*0.39)
     .rotationEffect(.degrees(-25 + sin(phase*0.8)*12))
     .offset(x:-size*0.12,y:-size*(0.24 + sound*0.035))
     .blur(radius:size*0.075)
    Ellipse().fill(Noir.crimsonDeep.opacity(0.85))
     .frame(width:size*1.15,height:size*0.36)
     .rotationEffect(.degrees(16 + sin(phase)*10))
     .offset(x:size*0.1,y:size*0.38).blur(radius:size*0.08)
   }
   .frame(width:size,height:size)
   .clipShape(contour)
   contour.stroke(LinearGradient(colors:[Color.white.opacity(0.35),Noir.crimsonLight.opacity(0.18),Noir.crimsonDeep.opacity(0.40)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1)
  }
  .frame(width:size,height:size)
  .drawingGroup()
  .accessibilityElement(children:.ignore)
  .accessibilityLabel("Friday, red orb")
  .accessibilityValue(activity)
 }

 private func current(_ i: Int,_ phase: Double) -> some View {
  let angle = phase * (0.6 + Double(i)*0.13) + Double(i)*1.9
  let colors = [Noir.crimsonLight,Color(red:1,green:0.55,blue:0.51),Noir.crimsonDeep,Noir.crimson,Color(red:1,green:0.72,blue:0.66)]
  return FridayContour(phase:angle,energy:0.4 + sound*0.6)
   .fill(LinearGradient(colors:[colors[i],colors[i].opacity(0.15)],startPoint:.topLeading,endPoint:.bottomTrailing))
   .frame(width:size*(0.88 + sound*0.12),height:size*0.76)
   .rotationEffect(.radians(angle))
   .offset(x:cos(angle)*size*0.23,y:sin(angle*0.9)*size*0.20)
   .blur(radius:size*0.07)
   .blendMode(i == 2 ? .multiply : .plusLighter)
   .opacity(i == 2 ? 0.80 : 0.62)
 }

 private func emoji(_ phase: Double) -> some View {
  ZStack {
   Circle().fill(RadialGradient(colors:[Noir.crimson.opacity(0.24),Noir.crimsonDeep.opacity(0.08)],center:.center,startRadius:0,endRadius:size*0.55))
   Circle().stroke(Noir.crimsonLight.opacity(0.28 + sound*0.4),lineWidth:1.5 + sound*2)
   Text(appearance.look.emoji(for:state))
    .font(.system(size:size*0.52))
    .rotationEffect(.degrees(moves && state == .thinking ? sin(phase*2)*6 : 0))
    .offset(y:moves && state == .speaking ? -sound*size*0.04 : 0)
  }
  .frame(width:size*0.88,height:size*0.88)
  .accessibilityElement(children:.ignore)
  .accessibilityLabel("Friday, \(appearance.look.title)")
  .accessibilityValue(activity)
 }

 private var appearanceMenu: some View {
  Menu {
   ForEach(FridayLook.allCases) { look in
    Button { appearance.look = look } label: {
     Label(look.title,systemImage:appearance.look == look ? "checkmark" : "circle")
    }
   }
  } label: {
   Label(appearance.look.title,systemImage:"face.smiling")
    .font(.system(size:10,weight:.medium,design:.rounded))
    .foregroundStyle(Color.white.opacity(0.72))
    .padding(.horizontal,10).padding(.vertical,5)
    .background(Capsule().fill(Color.white.opacity(0.06)))
  }
  .menuStyle(.borderlessButton)
  .fixedSize()
  .accessibilityLabel("Friday’s appearance")
  .accessibilityValue(appearance.look.title)
  .help("Choose the red orb or an emoji. Saved on this Mac.")
 }
}

// A smoothly curved outline: sound changes its shape without sharp jumps or spikes.
private struct FridayContour: Shape {
 var phase: Double
 var energy: Double
 func path(in rect: CGRect) -> Path {
  let count = 60
  let radius = Double(min(rect.width,rect.height)) * 0.46
  let points: [CGPoint] = (0..<count).map { i in
   let angle = Double(i) * 2 * .pi / Double(count)
   let ripple = sin(angle*3 + phase) * (0.022 + energy*0.032) + sin(angle*5 - phase*0.8) * (0.010 + energy*0.018)
   let r = radius * (1 + ripple)
   return CGPoint(x:Double(rect.midX) + cos(angle)*r,y:Double(rect.midY) + sin(angle)*r)
  }
  var path = Path()
  path.move(to:points[0])
  for i in 0..<count {
   let a = points[(i + count - 1) % count]
   let b = points[i]
   let c = points[(i + 1) % count]
   let d = points[(i + 2) % count]
   path.addCurve(to:c,
    control1:CGPoint(x:b.x + (c.x-a.x)/6,y:b.y + (c.y-a.y)/6),
    control2:CGPoint(x:c.x - (d.x-b.x)/6,y:c.y - (d.y-b.y)/6))
  }
  path.closeSubpath()
  return path
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
     LinearGradient(colors:[Color(red:0.15,green:0.10,blue:0.16),Color(red:0.08,green:0.07,blue:0.13)],startPoint:.topLeading,endPoint:.bottomTrailing)
     glow(Noir.crimson.opacity(0.30),x:0.16 + 0.05 * sin(t * 0.11),y:0.10 + 0.05 * cos(t * 0.09),radius:reach * 0.75)
     glow(Color(red:0.38,green:0.22,blue:0.66).opacity(0.26),x:0.86 + 0.05 * cos(t * 0.08),y:0.90 + 0.04 * sin(t * 0.10),radius:reach * 0.70)
     glow(Noir.crimsonDeep.opacity(0.38),x:0.55 + 0.06 * sin(t * 0.07),y:0.50 + 0.06 * cos(t * 0.06),radius:reach * 0.55)
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
   .background(Circle().fill(filled ? Noir.crimson : Color.white.opacity(0.08)))
   .overlay(Circle().stroke(filled ? Noir.crimsonLight.opacity(0.5) : Color.white.opacity(0.12),lineWidth:1))
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
