import SwiftUI
import AVFoundation

// Reads the Meeting Room out loud with the Mac's built-in voices: a different one for Claude, GPT, Friday and Matthew (see
// SpeechData.swift for what is said and how the voices are picked). Free and on this Mac only: nothing is sent anywhere. It speaks
// WRITTEN words from the board and the thread. It is not a live call with anyone.
@MainActor final class MeetingVoice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
 // What is being read right now ("board", "meeting", "crew-GPT", "m123"), or empty when quiet.
 @Published var playing = ""
 // Who is speaking this line, for the "now speaking" caption.
 @Published var speaker = ""
 private let synth = AVSpeechSynthesizer()
 private var queue: [SpeakLine] = []
 private var assignment: [String:String] = [:]
 private var generation = 0
 private var tokens: [ObjectIdentifier:Int] = [:]

 override init() {
  super.init()
  synth.delegate = self
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
  generation += 1
  queue = []
  tokens.removeAll()
  synth.stopSpeaking(at:.immediate)
  playing = ""
  speaker = ""
 }

 private func next() {
  guard !queue.isEmpty else {
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
  tokens[ObjectIdentifier(utterance)] = generation
  synth.speak(utterance)
 }

 nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,didFinish utterance: AVSpeechUtterance) {
  let key = ObjectIdentifier(utterance)
  Task { @MainActor in
   guard let started = self.tokens.removeValue(forKey:key), started == self.generation else { return }
   self.next()
  }
 }
}
