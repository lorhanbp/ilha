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
    private var statusIcon: StatusIcon?
    private let trigger = HoverTrigger()
    private var leaveTimer: Timer?
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
        accessories.onHardwareChange = { [weak self] in self?.popupGuard.burst() }
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
        statusIcon = StatusIcon { [weak self] in self?.showSettings() }
        state.$expanded.removeDuplicates().sink { [weak self] open in self?.system.active = open; self?.energy.active = open }.store(in: &subscriptions)
        popupGuard.onPopupOpened = { [weak self] in self?.hud.hold() }
        popupGuard.onPopupClosed = { [weak self] in self?.hud.release() }
        popupGuard.watch()
        mediaKeys.start()

        trigger.onEnter = { [weak self] in self?.state.expanded = true }
        positionTrigger()
        trigger.orderFrontRegardless()
        music.objectWillChange.merge(with: hud.objectWillChange).sink { [weak self] _ in
            DispatchQueue.main.async { self?.positionTrigger() }
        }.store(in: &subscriptions)
        state.$expanded.removeDuplicates().sink { [weak self] open in self?.expandedChanged(open) }.store(in: &subscriptions)
    }

    /// Faixa invisível sobre a ilha fechada: o macOS só avisa quando o mouse entra, sem ninguém ficar lendo a posição dele.
    private func positionTrigger() {
        let wing = IslandLayout.wing(hasTrack: music.hasTrack, hud: hud.visible, hudWing: hud.wing)
        let width = state.notchWidth + wing * 2
        // Estende 2 pt abaixo e vai até a borda de cima, onde o mouse encosta em y == maxY.
        trigger.setFrame(NSRect(x: panel.frame.midX - width / 2, y: panel.frame.maxY - state.notchHeight - 2,
                                width: width, height: state.notchHeight + 2), display: false)
    }

    private func expandedChanged(_ open: Bool) {
        panel.ignoresMouseEvents = !open
        trigger.ignoresMouseEvents = open
        leaveTimer?.invalidate()
        leaveTimer = nil
        guard open else { return }
        // Só enquanto a ilha está aberta: confere se o mouse saiu dela.
        leaveTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkMouseLeft() }
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

    private func checkMouseLeft() {
        let visible = NSRect(x: panel.frame.midX - IslandLayout.panelSize.width / 2,
                             y: panel.frame.maxY - state.expandedHeight,
                             width: IslandLayout.panelSize.width, height: state.expandedHeight + 60)
        if !visible.contains(NSEvent.mouseLocation) { state.expanded = false }
    }
}

/// Janela quase transparente (1% de preto) só para receber o aviso de entrada do mouse.
final class HoverTrigger: NSPanel {
    var onEnter: () -> Void = {}

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = HoverView()
        view.onEnter = { [weak self] in self?.onEnter() }
        contentView = view
    }
}

final class HoverView: NSView {
    var onEnter: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { onEnter() }
}
