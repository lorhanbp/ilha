---
title: "Seeking and play/pause for a YouTube Music web app must go through the app's own keys and buttons, because macOS drops its playback session and ignores seek co…"
author: Lorhanborgespaixao
date: 2026-11-17
branch: main
cost: { minutes: 162, tokens: 506275 }
id: l-dc8b314c
scope: repo
status: active
src: agent
touches:
  - LICENSE
  - README.md
  - Sources/Ilha/AppDelegate.swift
  - Sources/Ilha/ClipboardPicker.swift
  - Sources/Ilha/ClipboardStore.swift
  - Sources/Ilha/IslandView.swift
  - Sources/Ilha/MediaKeys.swift
  - Sources/Ilha/Settings.swift
  - Package.swift
  - Sources/Ilha/AccessoryMonitor.swift
---

## Decided
- Read what is playing by loading a small library into /usr/bin/perl (an Apple-signed binary), because on macOS 15.4+ the private MediaRemote answers only Apple-signed programs.
- Control the YouTube Music web app through Accessibility: press the "Tocar/Pausar/Avançar/Anterior" buttons in its "Barra do player" toolbar. This works without bringing the app to the front.
- Pause is kept in the island by remembering the last track ourselves; macOS drops the session about 15 s after a pause and then sends the play key to Apple Music.
- When no session is live, swallow F7/F8/F9 in an event tap and press the web app's play button instead.
- Seeking sends the player's J/L keys (10 s each) after activating the app; the app's window is parked at the bottom-left corner so activation shows almost nothing.
- Sign every build with one fixed local certificate ("Ilha Dev"), otherwise the permission is lost on each rebuild.

## Tried and ruled out
- MediaRemote seek, skip-10 and set-elapsed-time commands: accepted, no effect on this player.
- Writing the seek slider's AXValue, AXIncrement, clicking at a position, number keys 0-9: no effect.
- Posting keys straight to the app's process, or focusing its window through Accessibility: the keys are ignored while it is in the background, and focusing raises the window anyway.
- A 10 s skip that flashes the player window: rejected by the user; hence the parked window.

## Watch out
- In macOS 27 the Accessibility pane lists only assistive apps; apps that capture keys or control others live under "System & App Protection Override", and a changed signature loses that entry.
- A pointer pushed to the very top edge sits at y == maxY, which NSRect.contains treats as outside; extend hover rectangles upward or the island flickers.
- With the Command Line Tools only, the SwiftUI @State macro is unavailable; use ObservableObject.
- macOS clamps a window moved off-screen to keep about 44 px visible (x -1326, y 916 on a 1470x956 screen).

In the code: native/adapter.m, native/np.pl, Sources/Ilha/YTMusic.swift, Sources/Ilha/MediaKeys.swift, Sources/Ilha/MusicModel.swift, build.sh, scripts/make-cert.sh.
