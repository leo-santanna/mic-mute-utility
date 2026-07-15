# Discord announcement message

---

Hey everyone! 👋

If you're on **macOS** and frustrated that the Wave Controller app has no keyboard shortcut for muting, I built a small free utility that solves exactly that.

**WaveMute** is an open source menu bar app that lets you mute and unmute your Wave mic with any global hotkey you configure (I use the F9 mute key on my keyboard). Here's what it does:

- Press your hotkey and the mic mutes at the hardware level — the front LED turns red just like when you tap the physical button
- The physical button on the mic still works and stays in sync with the app
- If you use **Google Meet**, muting via the hotkey or the physical button also mutes you inside the call automatically — and if you click mute inside Meet, the mic LED follows too
- No CoreAudio involvement, so you never get the "microphone muted by system" warning from meeting apps
- Configurable shortcut, launch at login, lives quietly in the menu bar

**Download:** https://github.com/leo-santanna/mic-mute-utility/releases/latest

Unzip, drag to Applications, right-click > Open on first launch (it's not notarized yet), and you're set. It's free and the source code is all there if you want to dig in.

Happy to answer any questions!

---
