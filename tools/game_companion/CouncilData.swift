import Foundation

// Phase 1A only: local, deterministic test conversations. No API calls, secrets, network,
// external tools, or public GitHub messages. The UI owns scheduling and cancellation.
enum CouncilSpeaker: String, CaseIterable, Codable {
 case matthew = "Matthew"
 case roxy = "Roxy"
 case claude = "Claude"
 case grok = "Grok"
}

enum CouncilTurnState: String, Codable {
 case streaming, complete, failed, stopped
}

enum CouncilSessionState: String, Codable {
 case idle, running, complete, stopped
}

struct CouncilTurn: Identifiable, Equatable, Codable {
 let id: UUID
 let speaker: CouncilSpeaker
 var text: String
 var state: CouncilTurnState
 let date: Date
}

struct CouncilRequest: Identifiable {
 let id: UUID
 let generation: Int
 let speaker: CouncilSpeaker
 // Completed prior messages only. No network transport or storage is provided here.
 let context: [CouncilTurn]
}

struct CouncilLimits: Equatable {
 let maxAgentTurns: Int
 let maxUserTurns: Int
 let maxInputCharacters: Int
 let maxOutputCharacters: Int
 let maxContextCharacters: Int

 init(maxAgentTurns: Int = 6, maxUserTurns: Int = 6, maxInputCharacters: Int = 2_000,
      maxOutputCharacters: Int = 1_200, maxContextCharacters: Int = 12_000) {
  self.maxAgentTurns = max(1,min(maxAgentTurns,6))
  self.maxUserTurns = max(1,min(maxUserTurns,6))
  self.maxInputCharacters = max(1,min(maxInputCharacters,2_000))
  self.maxOutputCharacters = max(1,min(maxOutputCharacters,1_200))
  self.maxContextCharacters = max(2_000,min(maxContextCharacters,12_000))
 }
}

// Value type deliberately free of @State, @AppStorage, actors, timers, and dependencies.
// The owner should call all mutations serially (e.g., from a @MainActor view model).
// Each request carries an ID + generation: late output after Interrupt/Stop is rejected.
struct CouncilSession: Identifiable {
 let id = UUID()
 private(set) var state: CouncilSessionState = .idle
 private(set) var turns: [CouncilTurn] = []
 private(set) var pending: [CouncilSpeaker] = []
 private(set) var agentTurnsUsed = 0
 private(set) var generation = 0
 private(set) var lastError: String? = nil
 let limits: CouncilLimits
 private var activeTurnID: UUID? = nil

 static let speakingOrder: [CouncilSpeaker] = [.roxy,.claude,.grok,.roxy,.claude,.grok]

 init(limits: CouncilLimits = CouncilLimits()) { self.limits = limits }

 var active: Bool { activeTurnID != nil }
 var canInterrupt: Bool { state == .running && turns.filter { $0.speaker == .matthew }.count < limits.maxUserTurns && agentTurnsUsed < limits.maxAgentTurns }

 // Starting twice cannot duplicate the queue or issue an unplanned API request.
 @discardableResult mutating func start(_ prompt: String) -> Bool {
  guard state == .idle, let words = validInput(prompt) else { return false }
  generation += 1
  turns = [CouncilTurn(id:UUID(),speaker:.matthew,text:words,state:.complete,date:Date())]
  pending = Array(Self.speakingOrder.prefix(limits.maxAgentTurns))
  state = .running
  lastError = nil
  return true
 }

 // Caller asks for the next request only after previous turn is complete.
 // A request is a permission to run exactly one turn, not a network operation.
 mutating func next() -> CouncilRequest? {
  guard state == .running, activeTurnID == nil else { return nil }
  guard agentTurnsUsed < limits.maxAgentTurns, !pending.isEmpty else {
   pending = []
   state = .complete
   return nil
  }
  let context = contextWindow()
  let speaker = pending.removeFirst()
  let id = UUID()
  activeTurnID = id
  agentTurnsUsed += 1  // failed/interrupted attempts consume the cap, preventing loops
  turns.append(CouncilTurn(id:id,speaker:speaker,text:"",state:.streaming,date:Date()))
  return CouncilRequest(id:id,generation:generation,speaker:speaker,context:context)
 }

 // Returns false when the request has expired or the output cap has been reached.
 @discardableResult mutating func append(_ chunk: String, for request: CouncilRequest) -> Bool {
  guard valid(request), let i = turns.indices.last, turns[i].state == .streaming else { return false }
  let remaining = limits.maxOutputCharacters - turns[i].text.count
  guard remaining > 0, !chunk.isEmpty else { return false }
  turns[i].text += String(chunk.prefix(remaining))
  return chunk.count <= remaining
 }

 @discardableResult mutating func finish(_ request: CouncilRequest, error: String? = nil) -> Bool {
  guard valid(request), let i = turns.indices.last, turns[i].state == .streaming else { return false }
  activeTurnID = nil
  if let error = error {
   turns[i].state = .failed
   lastError = String(error.prefix(200))
   pending = []
   state = .complete
  } else if turns[i].text.isEmpty {
   turns[i].state = .failed
   lastError = "No response was received."
   pending = []
   state = .complete
  } else {
   turns[i].state = .complete
   if pending.isEmpty || agentTurnsUsed >= limits.maxAgentTurns { state = .complete }
  }
  return true
 }

 // A Matthew interruption supersedes the old queue. The UI must cancel its task
 // when this returns true; a late chunk or finish will be rejected either way.
 @discardableResult mutating func interrupt(with message: String) -> Bool {
  guard canInterrupt, let words = validInput(message) else { return false }
  invalidateActive()
  generation += 1
  turns.append(CouncilTurn(id:UUID(),speaker:.matthew,text:words,state:.complete,date:Date()))
  let remaining = limits.maxAgentTurns - agentTurnsUsed
  pending = Array(Self.speakingOrder.prefix(remaining))
  lastError = nil
  return true
 }

 // Hard stop: no future calls to next, append, or finish can revive this session.
 mutating func stop() {
  guard state != .stopped else { return }
  invalidateActive()
  generation += 1
  pending = []
  state = .stopped
 }

 private mutating func invalidateActive() {
  if let id = activeTurnID, let i = turns.indices.last, turns[i].id == id {
   turns[i].state = .stopped
  }
  activeTurnID = nil
 }

 private func valid(_ request: CouncilRequest) -> Bool {
  state == .running && request.generation == generation && request.id == activeTurnID && turns.last?.id == request.id
 }

 private func validInput(_ text: String) -> String? {
  let words = text.trimmingCharacters(in:.whitespacesAndNewlines)
  return !words.isEmpty && words.count <= limits.maxInputCharacters ? words : nil
 }

 private func contextWindow() -> [CouncilTurn] {
  var chosen: [CouncilTurn] = []
  var used = 0
  for turn in turns.reversed() where turn.state == .complete {
   let cost = turn.text.count
   if used + cost > limits.maxContextCharacters { break }
   chosen.append(turn)
   used += cost
  }
  return chosen.reversed()
 }
}

// Deliberately obvious fixtures: no reply can be mistaken for a real Claude, Grok,
// or OpenAI model call. Each references the actual prior completed messages.
enum CouncilTestProvider {
 static func reply(to request: CouncilRequest) -> String {
  let user = request.context.last { $0.speaker == .matthew }?.text ?? "(no prompt)"
  let previous = request.context.last { $0.speaker != .matthew }
  let reference = previous.map { "I received \($0.speaker.rawValue)'s earlier test turn: \(String($0.text.prefix(55)))" } ?? "I am the first agent in this test round."
  return "[test reply] \(request.speaker.rawValue) received Matthew's prompt: \(String(user.prefix(65))). \(reference) This is a scripted test, not a real AI response."
 }
}
