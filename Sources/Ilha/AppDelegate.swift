import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private let music = MusicModel()
    private var state: IslandState!
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()
    private let hud = HUDModel()
    private let popupGuard = NativePopupGuard()
    private let clipboard = ClipboardStore()
    private let energy = EnergyModel()
    private let accessories = AccessoryMonitor()
    private let system = SystemMonitor()
    private lazy var picker = ClipboardPicker(store: clipboard)
    private lazy var mediaKeys = MediaKeys(music: music, hud: hud)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        var notchWidth: CGFloat = 200
        var notchHeight: CGFloat = 32
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - left.width - right.width
            notchHeight = screen.safeAreaInsets.top
        }
        state = IslandState(notchWidth: notchWidth, notchHeight: notchHeight)
        state.openSettings = { [weak self] in self?.showSettings() }

        let size = IslandLayout.panelSize
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: IslandView(music: music, state: state, hud: hud, clipboard: clipboard,
                                                           energy: energy, accessories: accessories, system: system))
        panel.orderFrontRegardless()
        mediaKeys.onClipboardShortcut = { [weak self] in self?.picker.toggle() }
        mediaKeys.onKey = { [weak self] code in self?.picker.handleKey(code) ?? false }
        accessories.onAnnounce = { [weak self] device, connected in
            let text = connected ? (device.battery ?? "Conectado") : "Desconectado"
            self?.hud.showAccessory(symbol: device.symbol, text: text)
        }
        energy.$plugged.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let self else { return }
                self.hud.showBattery(percent: self.energy.percent, charging: self.energy.plugged)
            }
        }.store(in: &subscriptions)
        if Bundle.main.bundlePath.hasPrefix("/Applications"), SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
        mediaKeys.start()
        popupGuard.start()

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.mouseMoved() }
        }
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 610),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Ajustes da Ilha"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: .shared))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func mouseMoved() {
        panel.ignoresMouseEvents = !state.expanded
        let mouse = NSEvent.mouseLocation
        let screenFrame = panel.frame
        let top = screenFrame.maxY
        let compactWidth = state.notchWidth + IslandLayout.wing(hasTrack: music.hasTrack, hud: hud.visible, hudWing: hud.wing) * 2
        // O mouse na borda de cima fica em y == maxY, que o NSRect.contains não conta: estende pra cima.
        let hover = NSRect(x: screenFrame.midX - compactWidth / 2, y: top - state.notchHeight - 2,
                           width: compactWidth, height: state.notchHeight + 60)
        if state.expanded {
            let visible = NSRect(x: panel.frame.midX - IslandLayout.panelSize.width / 2,
                                 y: panel.frame.maxY - state.expandedHeight,
                                 width: IslandLayout.panelSize.width, height: state.expandedHeight + 60)
            if !visible.contains(mouse) { state.expanded = false }
        } else if hover.contains(mouse) {
            state.expanded = true
        }
    }
}
