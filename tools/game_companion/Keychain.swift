import Foundation
import Security

// One place for the app's secrets (the Google key, the Twitch login, the GitHub posting key, the Stripe read-only key).
//
// They used to live in the macOS Keychain, and macOS asked for the Mac password again after every rebuild, even after
// "Always Allow": the old Keychain ties its permission to the exact build of the app, and a self-made certificate can't make
// that stable. So they now live in small private files (see SecretFile.swift): a folder only this Mac account can open.
// What this changes, honestly: the Keychain encrypts each secret; a private file does not (FileVault, which encrypts the
// whole disk, still does). Other software running as the same user could read either one, because the earlier "allow all
// applications" setting already let it. Nothing is in the repo, in settings or in chat. The keys are free or revocable.
//
// Old Keychain items are copied into files once at start (migrateLegacy), which is the last time macOS can ask for the
// password; each old item is deleted after it is copied.
enum Keychain {
 nonisolated(unsafe) private static var cache: [String:Data] = [:]
 private static let migratedKey = "secrets.migrated.v1"

 private static func base(_ service: String) -> [String:Any] {
  [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service]
 }

 private static var migrated: Bool { UserDefaults.standard.bool(forKey:migratedKey) }

 // Reads only the old item's label, which never asks for a password.
 private static func legacyExists(_ service: String) -> Bool {
  var query = base(service)
  query[kSecReturnAttributes as String] = true
  query[kSecMatchLimit as String] = kSecMatchLimitOne
  return SecItemCopyMatching(query as CFDictionary,nil) == errSecSuccess
 }

 // This is the call that can ask for the password (old items only).
 private static func legacyRead(_ service: String) -> Data? {
  var query = base(service)
  query[kSecReturnData as String] = true
  query[kSecMatchLimit as String] = kSecMatchLimitOne
  var item: CFTypeRef?
  guard SecItemCopyMatching(query as CFDictionary,&item) == errSecSuccess else { return nil }
  return item as? Data
 }

 private static func legacyRemove(_ service: String) { SecItemDelete(base(service) as CFDictionary) }

 // Copies each old Keychain item into a private file, once. Runs at start; any password box macOS shows now is the last one.
 static func migrateLegacy(_ services: [String]) {
  guard !migrated else { return }
  // Only call it done when every old item was copied (or never existed). A failed copy is tried again next launch, and until then
  // read() still falls back to the old item.
  var allDone = true
  for service in services where !SecretFile.exists(service) && legacyExists(service) {
   if let data = legacyRead(service), SecretFile.write(service,data) {
    cache[service] = data
    legacyRemove(service)
   } else { allDone = false }
  }
  if allDone { UserDefaults.standard.set(true,forKey:migratedKey) }
 }

 // True if a secret is saved. Never asks for a password.
 static func exists(_ service: String) -> Bool {
  if cache[service] != nil || SecretFile.exists(service) { return true }
  return !migrated && legacyExists(service)
 }

 // The saved secret, or nil. Kept in memory after the first read.
 static func read(_ service: String) -> Data? {
  if let hit = cache[service] { return hit }
  if let data = SecretFile.read(service) { cache[service] = data; return data }
  guard !migrated, let data = legacyRead(service) else { return nil }
  if SecretFile.write(service,data) { legacyRemove(service) }
  cache[service] = data
  return data
 }

 @discardableResult
 static func write(_ service: String,_ data: Data) -> Bool {
  guard SecretFile.write(service,data) else { return false }
  cache[service] = data
  return true
 }

 static func remove(_ service: String) {
  SecretFile.remove(service)
  cache[service] = nil
  if legacyExists(service) { legacyRemove(service) }
 }
}
