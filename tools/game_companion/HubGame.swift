import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The Game page and the latest-clip card.
// Split out of Hub.swift on 2026-10-24 with no change in behaviour, so pages can have one owner each.
extension CompanionInterfaceView {
 // MARK: game, accounts, coming soon

 var hubGame: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:18) {
    LazyVGrid(columns:[GridItem(.adaptive(minimum:200),spacing:14)],spacing:14) {
     hubStat(live.sees == 0 ? "What she sees" : "Game window",live.sees == 0 ? "All screens" : (c.sharing ? "Shared" : "None chosen"),live.sees == 0 ? "Everything on every screen goes to Google while she is live" : (c.sharing ? "Friday can see it" : "Choose one to start"),tint:live.sees == 0 || c.sharing ? HubColor.green : Color.white)
     hubStat("Friday",live.running ? "Live" : "Asleep",live.running ? (live.sees == 0 ? "All screens and mic are shared with Google" : "Window and mic are shared with Google") : "Nothing is being sent",tint:live.running ? Noir.crimsonLight : Color.white)
     hubStat("Google key",live.hasKey ? "Saved" : "Missing",live.hasKey ? "Saved privately on this Mac" : "Add it in Settings",tint:live.hasKey ? HubColor.green : Noir.crimsonLight)
    }
    HStack(spacing:12) {
     Button { hubSelect(.friday) } label: { Label("Open Friday",systemImage:"waveform") }.buttonStyle(PillButtonStyle())
     Button { c.choose() } label: { Label("Choose window",systemImage:"rectangle.on.rectangle") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
     Button { c.showPanel = true } label: { Label("Settings",systemImage:"slider.horizontal.3") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    }
    if c.tab == 0, let seen = live.lastSeen {
     VStack(alignment:.leading,spacing:10) {
      Text("What Friday saw last").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
      Image(nsImage:seen).resizable().scaledToFit().frame(height:150).clipShape(RoundedRectangle(cornerRadius:12,style:.continuous))
      Text("\(live.picturesSent) pictures sent this session. The preview stays in memory only.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.45))
     }
     .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
    }
    hubClipCard
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
 }

 // The latest Twitch clip: what the app did with it, and where the edited files are.
 @ViewBuilder var hubClipCard: some View {
  if !clips.status.isEmpty || !clips.editStatus.isEmpty {
   VStack(alignment:.leading,spacing:10) {
    HStack(spacing:8) {
     Text("Latest clip").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
     if clips.editing { ProgressView().controlSize(.small) }
    }
    if !clips.status.isEmpty { Text(clips.status).font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.7)).textSelection(.enabled) }
    if !clips.editStatus.isEmpty { Text(clips.editStatus).font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.7)).textSelection(.enabled) }
    HStack(spacing:10) {
     if let folder = clips.lastFolder { Button { NSWorkspace.shared.open(folder) } label: { Label("Show the edited clip",systemImage:"folder") }.buttonStyle(PillButtonStyle()) }
     if !clips.lastClipURL.isEmpty, let url = URL(string:clips.lastClipURL) { Button { NSWorkspace.shared.open(url) } label: { Label("Open on Twitch",systemImage:"arrow.up.right") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12))) }
    }
   }
   .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
  }
 }
}
