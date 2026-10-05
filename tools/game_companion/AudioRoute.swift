import CoreAudio
import Foundation

// Is the Mac playing through headphones, or through speakers? On speakers the microphone hears Friday's own voice, so the app
// pauses the mic while she talks (see LiveBuddy.sendAudio). On headphones it can stay open, so Matthew can interrupt her.
// When this can't tell, it answers "speakers": pausing the mic only costs the chance to interrupt, while a wrong
// "headphones" makes her hear herself and cut off.
enum AudioRoute {
 // Built-in output with the headphone jack in use, or Bluetooth (AirPods and similar). Anything else counts as speakers,
 // including HDMI/monitor speakers, AirPlay and USB (a USB headset can be set by hand in Settings).
 static func headphonesInUse() -> Bool {
  var device = AudioObjectID(kAudioObjectUnknown)
  var size = UInt32(MemoryLayout<AudioObjectID>.size)
  var address = AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultOutputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
  guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&device) == noErr, device != AudioObjectID(kAudioObjectUnknown) else { return false }
  var transport: UInt32 = 0
  size = UInt32(MemoryLayout<UInt32>.size)
  address = AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyTransportType,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
  guard AudioObjectGetPropertyData(device,&address,0,nil,&size,&transport) == noErr else { return false }
  if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE { return true }
  guard transport == kAudioDeviceTransportTypeBuiltIn else { return false }
  // The built-in output says which port is in use: 'hdpn' is the headphone jack, 'ispk' the internal speakers.
  var source: UInt32 = 0
  size = UInt32(MemoryLayout<UInt32>.size)
  address = AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyDataSource,mScope:kAudioObjectPropertyScopeOutput,mElement:kAudioObjectPropertyElementMain)
  guard AudioObjectGetPropertyData(device,&address,0,nil,&size,&source) == noErr else { return false }
  return source == 0x6864_706E
 }
}
