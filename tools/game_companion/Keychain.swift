import Foundation
import Security

// One place for the app's Keychain secrets (the Google key and the Twitch login).
// It fixes the "enter your password" box that came back after every rebuild:
//  1. Asking "is it saved?" reads only the item's label, which never asks for a password. (The app used to read the
//     secret itself at every launch, once per item.)
//  2. The secret is read only when it is needed, once per run, and kept in memory after that.
//  3. Items are saved so any application running as the player may read them without asking, which is the Keychain's
//     "Allow all applications to access this item" setting. Old items are re-saved that way after the next successful read.
// The secret stays in the login Keychain, encrypted and locked with the Mac login. The tradeoff: other software running
// as the same user could read it without a prompt. That is fine for a free API key; it would not be for a bank password.
enum Keychain {
 nonisolated(unsafe) private static var cache: [String:Data] = [:]

 private static func base(_ service: String) -> [String:Any] {
  [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service]
 }
 private static func openFlag(_ service: String) -> String { "keychain.open.\(service)" }

 // True if an item is saved. Reads only its label, so macOS never asks for a password.
 static func exists(_ service: String) -> Bool {
  if cache[service] != nil { return true }
  var query = base(service)
  query[kSecReturnAttributes as String] = true
  query[kSecMatchLimit as String] = kSecMatchLimitOne
  return SecItemCopyMatching(query as CFDictionary,nil) == errSecSuccess
 }

 // Reads the secret. This is the call that can ask for a password, so it happens once per run.
 static func read(_ service: String) -> Data? {
  if let hit = cache[service] { return hit }
  var query = base(service)
  query[kSecReturnData as String] = true
  query[kSecMatchLimit as String] = kSecMatchLimitOne
  var item: CFTypeRef?
  guard SecItemCopyMatching(query as CFDictionary,&item) == errSecSuccess, let data = item as? Data else { return nil }
  cache[service] = data
  // One time only: an item made by an older build still asks. Re-save it so no application is asked again.
  if !UserDefaults.standard.bool(forKey:openFlag(service)) {
   let result = store(service,data)
   if result.saved { UserDefaults.standard.set(result.open,forKey:openFlag(service)) }
  }
  return data
 }

 @discardableResult
 static func write(_ service: String,_ data: Data) -> Bool {
  let result = store(service,data)
  if result.saved {
   cache[service] = data
   UserDefaults.standard.set(result.open,forKey:openFlag(service))
  }
  return result.saved
 }

 static func remove(_ service: String) {
  SecItemDelete(base(service) as CFDictionary)
  cache[service] = nil
  UserDefaults.standard.removeObject(forKey:openFlag(service))
 }

 // Saves with "any application may use this" access. If that can't be set up, it falls back to a normal save, so the
 // secret is never lost over this.
 private static func store(_ service: String,_ data: Data) -> (saved: Bool,open: Bool) {
  SecItemDelete(base(service) as CFDictionary)
  var add = base(service)
  add[kSecValueData as String] = data
  if let access = anyAppAccess(service) {
   add[kSecAttrAccess as String] = access
   if SecItemAdd(add as CFDictionary,nil) == errSecSuccess { return (true,true) }
   add[kSecAttrAccess as String] = nil
   SecItemDelete(base(service) as CFDictionary)
  }
  return (SecItemAdd(add as CFDictionary,nil) == errSecSuccess,false)
 }

 // An access object whose every rule says "any application may use this without asking". Returns nil if macOS refuses.
 private static func anyAppAccess(_ label: String) -> SecAccess? {
  var created: SecAccess?
  guard SecAccessCreate(label as CFString,nil,&created) == errSecSuccess, let access = created else { return nil }
  var listed: CFArray?
  guard SecAccessCopyACLList(access,&listed) == errSecSuccess, let rules = listed as? [AnyObject] else { return nil }
  for rule in rules {
   let acl = unsafeBitCast(rule,to:SecACL.self)
   var apps: CFArray?
   var description: CFString?
   var selector = SecKeychainPromptSelector()
   guard SecACLCopyContents(acl,&apps,&description,&selector) == errSecSuccess else { return nil }
   // A nil application list means any application; an empty prompt selector means never ask for a passphrase.
   guard SecACLSetContents(acl,nil,description ?? (label as CFString),SecKeychainPromptSelector(rawValue:0)) == errSecSuccess else { return nil }
  }
  return access
 }
}
