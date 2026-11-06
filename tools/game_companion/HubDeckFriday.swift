import SwiftUI
import AppKit

// Friday's own page (Signal Deck). The big orb and the round control row are the real, working ones (hands, keyboard, big voice button, clip,
// close); under them sit four small cards: the three orb states with the current one marked, what she is doing, memory and music.
// Nothing here starts anything by itself.
extension CompanionInterfaceView {
 var deckFriday: some View {
  GeometryReader { geo in
   let tight = hub.compact || geo.size.height < 560
   let showCards = !hub.compact && geo.size.height >= 640
   VStack(spacing:0) {
    fridayStage(orb:tight ? min(max(geo.size.height * 0.26,80),200) : min(max(geo.size.height * 0.30,140),300),tight:tight)
     .frame(maxWidth:620)
     .frame(maxWidth:.infinity)
    // Everything under the orb scrolls, so the box, the cards and the Switchboard never squeeze the orb out of the window.
    ScrollView {
     VStack(spacing:0) {
      // Friday Phase 1 "She thinks" (FridayBrain.swift): one text box + Send, answered by Claude with no tools.
      FridayChatBox(compact:tight).padding(.horizontal,22).padding(.bottom,12)
      if showCards {
       HStack(alignment:.top,spacing:12) {
        deckStatesCard
        deckDoingCard
        deckMemoryCard
        deckMusicCard
       }
       .padding(.horizontal,22).padding(.bottom,18)
      }
      // Friday's Switchboard (HubSwitchboard.swift): its on/off switch and job log.
      SwitchboardPanel(compact:!showCards).padding(.horizontal,22).padding(.bottom,14)
     }
    }
    .scrollIndicators(.hidden)
   }
  }
  .background(HubTheme.background.opacity(0.0))
 }

 var deckStatesCard: some View {
  deckCard {
   deckLabel("ORB STATES")
   TimelineView(.animation(minimumInterval:1.0/24.0,paused:reduceMotion)) { timeline in
    let now = timeline.date
    let current = orbState(at:now)
    HStack(spacing:4) {
     ForEach([(OrbState.idle,"IDLE","breathes"),(OrbState.listening,"LISTENS","ripples"),(OrbState.speaking,"SPEAKS","pulses")],id:\.1) { entry in
      let on = current == entry.0 || (entry.0 == .idle && (current == .off || current == .thinking))
      VStack(spacing:0) {
       FridayOrb(state:entry.0,t:now.timeIntervalSinceReferenceDate,level:entry.0 == .idle ? 0 : 0.35 + 0.25 * sin(now.timeIntervalSinceReferenceDate * 3 + Double(entry.1.count)),size:26,animated:!reduceMotion,showsPicker:false)
        .frame(height:44).scaleEffect(0.78)
       Text(entry.1).font(.system(size:8.5,weight:.bold,design:.monospaced)).foregroundStyle(on ? HubTheme.green : HubTheme.subtext)
       Text(entry.2).font(.system(size:9)).foregroundStyle(HubTheme.subtext)
      }
      .frame(maxWidth:.infinity).opacity(on ? 1 : 0.55)
     }
    }
   }
  }
  .accessibilityElement(children:.combine).accessibilityLabel("Orb states: idle breathes, listening ripples, speaking pulses")
 }

 var deckDoingCard: some View {
  deckCard {
   deckLabel("WHAT SHE'S DOING")
   ForEach(Array(deckDoingLines.enumerated()),id:\.offset) { _,line in
    Text(line).font(.system(size:12)).foregroundStyle(HubTheme.text).lineLimit(3)
   }
   if c.tab == 0 && live.running && !live.heard.isEmpty {
    Text("heard: \(MeetingData.brief(live.heard,limit:60))").font(.system(size:11)).foregroundStyle(HubTheme.subtext).lineLimit(2)
   }
  }
 }

 var deckMemoryCard: some View {
  let recent = Array(conversation.notes.suffix(3).reversed())
  return deckCard {
   deckLabel(conversation.memoryEnabled ? "MEMORY · \(conversation.notes.count) NOTES" : "MEMORY · OFF")
   if !conversation.memoryEnabled {
    Text("Memory is off. Notes are only saved if you turn it on in Settings.").font(.system(size:12)).foregroundStyle(HubTheme.subtext)
   } else if recent.isEmpty {
    Text("No notes saved yet.").font(.system(size:12)).foregroundStyle(HubTheme.subtext)
   } else {
    ForEach(recent) { note in Text(note.text).font(.system(size:12)).foregroundStyle(HubTheme.text).lineLimit(2) }
   }
   Button { c.showPanel = true } label: { Text("Open memory settings ›").font(.system(size:11,design:.monospaced)).foregroundStyle(HubTheme.teal) }.buttonStyle(.plain)
  }
 }

 var deckMusicCard: some View {
  deckCard {
   deckLabel("MUSIC")
   if live.spotifyInstalled {
    Text("Friday works Spotify by voice: play, pause, skip, or what's playing. Nothing plays unless you ask.").font(.system(size:12)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
    Button { if let url = URL(string:"spotify:") { NSWorkspace.shared.open(url) } } label: { Label("Open Spotify",systemImage:"music.note").font(.system(size:11.5,weight:.medium)).foregroundStyle(HubTheme.green) }.buttonStyle(.plain)
   } else {
    Text("Spotify isn't installed on this Mac.").font(.system(size:12)).foregroundStyle(HubTheme.subtext)
   }
  }
 }
}
