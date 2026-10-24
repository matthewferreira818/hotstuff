import SwiftUI
import Combine
import AVFoundation

// Reads the Meeting Room out loud with the Mac's built-in voices: a different one for Claude, GPT, Friday, Matthew and a Narrator for
// everything the app itself writes (see SpeechData.swift for what is said and how the voices are picked). Free and on this Mac only:
// nothing is sent anywhere. It speaks WRITTEN words from the board and the thread. It is not a live call with anyone.
@MainActor final class MeetingVoice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
 // What is being read right now ("board", "meeting", "crew-GPT", "m123"), or empty when quiet.
 @Published var playing = ""
 // Who is speaking this line, for the "now speaking" caption ("Narrator" for what the app wrote).
 @Published var speaker = ""
 private let synth = AVSpeechSynthesizer()
 private var queue: [SpeakLine] = []
 private var assignment: [String:String] = [:]
 // The line being spoken now; nil when quiet or after stop(). A late callback for any other line is ignored.
 private var current: AVSpeechUtterance?
 private var watch: AnyCancellable?

 override init() {
  super.init()
  synth.delegate = self
 }

 // Friday hears this Mac, so the moment she goes live every voice here stops, whether or not this page is on screen.
 func attach(_ live: LiveBuddy) {
  watch = live.$running.removeDuplicates().sink { [weak self] running in
   if running { self?.stop() }
  }
 }

 // Starts reading these lines under this name, or stops if that is already what is playing.
 func toggle(_ id: String,_ lines: [SpeakLine]) {
  if playing == id { stop() } else { play(id,lines) }
 }

 func play(_ id: String,_ lines: [SpeakLine]) {
  stop()
  guard !lines.isEmpty else { return }
  let voices = AVSpeechSynthesisVoice.speechVoices().map { SpeechData.VoiceInfo(id:$0.identifier,name:$0.name,language:$0.language,quality:$0.quality.rawValue) }
  assignment = SpeechData.assign(SpeechData.speakers,voices:voices)
  playing = id
  queue = lines
  next()
 }

 func stop() {
  queue = []
  current = nil
  synth.stopSpeaking(at:.immediate)
  playing = ""
  speaker = ""
 }

 private func next() {
  guard !queue.isEmpty else {
   current = nil
   playing = ""
   speaker = ""
   return
  }
  let line = queue.removeFirst()
  let utterance = AVSpeechUtterance(string:line.text)
  if let voiceID = assignment[line.speaker], let voice = AVSpeechSynthesisVoice(identifier:voiceID) { utterance.voice = voice }
  utterance.rate = AVSpeechUtteranceDefaultSpeechRate
  utterance.pitchMultiplier = SpeechData.pitch(line.speaker)
  utterance.postUtteranceDelay = 0.3
  speaker = line.speaker
  current = utterance
  synth.speak(utterance)
 }

 // A line ended, by finishing or by the system cancelling it. Only the line being spoken now moves things on.
 private func ended(_ utterance: AVSpeechUtterance) {
  guard utterance === current else { return }
  next()
 }

 nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,didFinish utterance: AVSpeechUtterance) {
  Task { @MainActor in self.ended(utterance) }
 }

 nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,didCancel utterance: AVSpeechUtterance) {
  Task { @MainActor in self.ended(utterance) }
 }
}
