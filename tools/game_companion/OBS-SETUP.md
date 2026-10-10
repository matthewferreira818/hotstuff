# Streaming the PS5 through OBS on the Mac, with a phone as the camera (free route)

Written 2026-10-10 for Matthew's setup: **PS5, Apple Silicon Mac, a phone for the camera, no capture card, no HDMI into the Mac.**
Everything marked *(verified)* was read on an official page that day. Everything marked *(test it)* is an inference nobody documents end to end,
so it has to be tried on his Mac first. Nothing here costs money. No stream key or password belongs in this file or in chat.

## Why OBS, and why the PlayStation's own streaming doesn't work for this

The PS5's built-in Twitch broadcast (Create → Broadcast) only uses a camera **plugged into the PS5** (Sony names two: the HD Camera and the
PlayStation Camera) *(verified; Sony doesn't say other webcams are unsupported, but names no way to use one)*. A camera that is not plugged into the console
goes into **OBS on the Mac**, which mixes the game and the camera into one picture and sends it to Twitch.

## The free route, step by step

1. **Mac check.** Apple menu → About This Mac. OBS 32.2.x needs **macOS 13.0 or newer** *(verified)*; on macOS 12 OBS says to install 32.1.2.
2. **Install OBS Studio** from obsproject.com/download: the **Apple Silicon** installer for an M-chip Mac. Open the file, drag OBS to Applications *(verified)*.
3. **Permissions.** When macOS asks, allow OBS **Screen Recording, Camera and Microphone**. If it never asked: OBS Studio menu → *Review App Permissions*.
   A black picture usually means a missing permission *(verified)*.
4. **PS Remote Play on the Mac** (free, from Sony's page remoteplay.dl.playstation.net/remoteplay/lang/en/index.html). On the PS5: *Settings → System →
   Remote Play → Enable Remote Play* *(verified)*. Sign in on the Mac with the same PlayStation account. Plug the controller into the Mac with a USB cable.
   Sony recommends at least 5 Mbps up and down, and 15 Mbps for the best result; a cable from the PS5 to the router beats Wi-Fi *(verified)*.
5. **The game into OBS.** In OBS press **+** under Sources → **macOS Screen Capture** → method **Window Capture** → pick the PS Remote Play window.
   If it is black or not listed, try **Application Capture**, then **Display Capture** *(test it: nobody documents PS5 Remote Play captured by OBS on current macOS;
   old PS4-era reports say Window Capture sometimes shows black and Display Capture works)*.
6. **Game sound.** **+** → **macOS Audio Capture** → pick the PS Remote Play app (or all desktop audio). OBS 30+ on macOS 13+ captures app audio with no extra
   driver *(verified for OBS in general; for Remote Play: test it)*. Watch the Audio Mixer meters move. One user reported audio dropping out after a few minutes on OBS 32.1.2; if
   it happens, say so.
7. **The camera (a phone).**
   - **iPhone XR or newer, iOS 16+:** Continuity Camera. Same Apple Account on both, Wi-Fi and Bluetooth on, phone near the Mac; or plug it in with a cable
     (tap Trust). In OBS: **+** → **Video Capture Device** → Create New → pick the iPhone in the Device list *(verified: Apple's requirements; test it: the exact name OBS shows)*.
   - **Android 14+ (Pixel verified):** plug in a data cable, tap the USB notification → Use USB for → **Webcam**. Other brands depend on the maker. A USB 2.0 cable may be
     needed on Mac (Android's docs say USB 3+ cables hit a bug in Apple's driver).
   - **Any phone, free:** DroidCam (free = standard definition; HD shows a watermark) or Camo (free = 720p, no watermark) *(verified on their pages)*.
8. **Build the scene.** Scenes → **+** → name it "Game + Face Cam". Add the game first (bottom), then the camera (it lands on top). Drag a corner of the camera to
   shrink it, then drag it to a corner. Add the mic: **+** → **Audio Input Capture** → your mic; don't pick the same mic again under Settings → Audio (echo).
   Twitch's own advice is separate scenes for Starting Soon, Gameplay, Be Right Back and Ending.
9. **Test before going live.** Press **Start Recording**, play 5 minutes, stop, watch the file: lag, dropped frames, sound out of step? Tell Claude: smooth, a bit
   laggy, or bad.
10. **Go live.** OBS → Settings → Stream → choose Twitch. Use **Connect Account** if it shows; otherwise use the stream key from the Twitch dashboard. **The stream key is
    a secret: paste it only into OBS yourself, never into chat.** Then Start Streaming, or ask Friday (she asks you to press Allow first).

## Honest limits

- **Remote Play is softer and a little laggy** compared with a capture card: the picture is compressed over the network. Sony's current pages give no maximum
  resolution or frame rate for PS5 Remote Play (a regular PS4 is documented at up to 720p). It is the only free route; it works for a start.
- With Remote Play you play **from the Mac window** with the controller on a USB cable to the Mac.
- If the free route is too laggy, the cheapest fix is an HDMI capture card (cheap ones about US$13 to $30 but unreliable; AVerMedia GC311 US$69.99 on sale;
  Elgato Neo US$129.99 / CA$169.99 as seen 2026-10-10). Those are money decisions: money mode applies, ask Matthew first. HDMI isn't available in his setup anyway.
- **Free TikTok fallback with no OBS:** on the PS5 press Create → *Save Recent Gameplay* (up to the last hour). *Settings → Captures and Broadcasts → Captures →
  Auto-Upload* sends clips to the PlayStation App on the phone (clips under 3 minutes, not 4K, for upload) *(verified)*.

## Friday and OBS

Once OBS is linked in the app (Stream page → OBS card; see README "OBS: Friday can work it"), Friday can check OBS, switch scenes, save a replay, mute the mic or the game
sound, and, only after Matthew presses Allow, go live or end the stream.
