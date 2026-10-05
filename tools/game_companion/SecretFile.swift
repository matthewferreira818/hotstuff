import Foundation

// Where the app keeps its logins and keys: one small private file per secret in
// ~/Library/Application Support/GameCompanion/secrets (folder readable only by this Mac account, files too).
// No Mac frameworks here, so it can be tested anywhere. See Keychain.swift for how it is used and why the Keychain was dropped.
enum SecretFile {
 static func folder() -> URL {
  FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("GameCompanion/secrets",isDirectory:true)
 }

 // Letters, digits, dot, dash and underscore only, so a service name can never point outside the folder.
 static func fileName(_ service: String) -> String {
  let safe = service.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" ? String($0) : "_" }.joined()
  return (safe.isEmpty ? "_" : safe) + ".secret"
 }

 static func url(_ service: String,in directory: URL) -> URL { directory.appendingPathComponent(fileName(service)) }

 static func exists(_ service: String,in directory: URL = folder()) -> Bool {
  FileManager.default.fileExists(atPath:url(service,in:directory).path)
 }

 static func read(_ service: String,in directory: URL = folder()) -> Data? {
  guard let data = try? Data(contentsOf:url(service,in:directory)), !data.isEmpty else { return nil }
  return data
 }

 @discardableResult
 static func write(_ service: String,_ data: Data,in directory: URL = folder()) -> Bool {
  guard !data.isEmpty else { return false }
  let manager = FileManager.default
  do {
   try manager.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
   try manager.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
   let target = url(service,in:directory)
   try data.write(to:target,options:.atomic)
   try manager.setAttributes([.posixPermissions:0o600],ofItemAtPath:target.path)
   return true
  } catch {
   return false
  }
 }

 static func remove(_ service: String,in directory: URL = folder()) {
  try? FileManager.default.removeItem(at:url(service,in:directory))
 }
}
