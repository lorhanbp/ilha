import AppKit
import ApplicationServices

/// Captura as teclas de mídia: volume e brilho viram o indicador da ilha; com a sessão solta, o play vai pro YT Music.
@MainActor
final class MediaKeys {
    private let music: MusicModel
    private let hud: HUDModel
    private var quitHold: Task<Void, Never>?
    private var holdSeconds: Double { Settings.shared.quitHoldSeconds }
    var onClipboardShortcut: () -> Void = {}
    var onKey: (Int64) -> Bool = { _ in false }
    private var tap: CFMachPort?

    init(music: MusicModel, hud: HUDModel) {
        self.music = music
        self.hud = hud
    }

    private func log(_ text: String) {
        let line = "\(Date()) \(text)\n"
        if let handle = FileHandle(forWritingAtPath: "/tmp/ilha.log") {
            handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
        } else { try? line.write(toFile: "/tmp/ilha.log", atomically: true, encoding: .utf8) }
    }

    func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        log("trusted=\(trusted) tap=\(tap != nil)")
        guard trusted else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
            return
        }
        install()
    }

    private func install() {
        guard tap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let keys = Unmanaged<MediaKeys>.fromOpaque(refcon).takeUnretainedValue()
            return MainActor.assumeIsolated { keys.handle(type: type, event: event) }
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask((1 << 14) | (1 << 10) | (1 << 11) | (1 << 12)), callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        log("tapCreate=\(tap != nil)")
        guard let tap else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func startQuit(_ app: NSRunningApplication) {
        quitHold?.cancel()
        hud.showQuit(seconds: holdSeconds)
        let seconds = holdSeconds
        quitHold = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            app.terminate()
            self?.hud.hide()
            self?.quitHold = nil
        }
    }

    private func cancelQuit() {
        guard quitHold != nil else { return }
        quitHold?.cancel()
        quitHold = nil
        hud.hide()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if type == .keyUp, event.getIntegerValueField(.keyboardEventKeycode) == 12 { cancelQuit(); return pass }
        if type == .flagsChanged {
            if !event.flags.contains(.maskCommand) { cancelQuit() }
            return pass
        }
        if type == .keyDown {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let repeating = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if Settings.shared.recording {
                if code == 53 { Settings.shared.recording = false; return nil }
                if !flags.intersection(Settings.relevantFlags).isEmpty {
                    let label = NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? "?"
                    Settings.shared.setShortcut(code: code, flags: flags, label: label)
                    return nil
                }
                return pass
            }
            if Settings.shared.quitHoldEnabled, code == 12, flags.contains(.maskCommand), flags.isDisjoint(with: [.maskAlternate, .maskControl, .maskShift]),
               let app = NSWorkspace.shared.frontmostApplication, Settings.shared.protectedApps.contains(app.bundleIdentifier ?? "") {
                if !repeating { startQuit(app) }
                return nil
            }
            if Settings.shared.matches(code: code, flags: flags) {
                if !repeating { onClipboardShortcut() }
                return nil
            }
            if onKey(code) { return nil }
            return pass
        }
        guard type.rawValue == 14, let key = NSEvent(cgEvent: event), key.subtype.rawValue == 8 else { return pass }
        let code = (key.data1 & 0xFFFF0000) >> 16
        let down = ((key.data1 & 0xFF00) >> 8) == 0xA
        switch code {
        case 16...20:
            log("tecla \(code) down=\(down) sessionLive=\(music.sessionLive)")
            guard !music.sessionLive else { return pass }
            if down && code == 16 { Task.detached { await YTMusic.resume() } }
            return nil
        case 0, 1, 7:
            guard var volume = SystemControls.volume() else { return pass }
            if down {
                let step: Float = 1.0 / 16
                if code == 7 {
                    SystemControls.setMuted(!SystemControls.muted())
                } else {
                    if SystemControls.muted() { SystemControls.setMuted(false) }
                    volume += code == 0 ? step : -step
                    _ = SystemControls.setVolume(volume)
                }
                hud.show(.volume, level: SystemControls.volume() ?? volume, muted: SystemControls.muted())
            }
            return nil
        case 2, 3:
            guard let brightness = SystemControls.brightness() else { return pass }
            if down {
                let value = brightness + (code == 2 ? 1.0 / 16 : -1.0 / 16)
                _ = SystemControls.setBrightness(value)
                hud.show(.brightness, level: SystemControls.brightness() ?? value)
            }
            return nil
        default:
            return pass
        }
    }
}
