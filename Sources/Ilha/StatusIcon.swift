import AppKit
import CoreWLAN
import IOKit.ps

/// Ícone único na barra de menu: arco = bateria, wifi no meio, wifi no meio mostra a força do sinal, raio deitado embaixo acende quando carrega.
@MainActor
final class StatusIcon {
    private let item = NSStatusBar.system.statusItem(withLength: 22)
    private var last = ""

    init(openSettings: @escaping () -> Void) {
        let settings = NSMenuItem(title: "Ajustes da Ilha", action: #selector(settingsClicked), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.openSettings = openSettings
        refresh()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let icon = Unmanaged<StatusIcon>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { icon.refresh() } }
        }, Unmanaged.passUnretained(self).toOpaque()).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let client = CWWiFiClient.shared()
        wifiEvents.onChange = { DispatchQueue.main.async { MainActor.assumeIsolated { [weak self] in self?.refresh() } } }
        client.delegate = wifiEvents
        try? client.startMonitoringEvent(with: .linkQualityDidChange)
        try? client.startMonitoringEvent(with: .ssidDidChange)
        try? client.startMonitoringEvent(with: .powerDidChange)
    }

    private let wifiEvents = WifiEvents()
    private var openSettings: () -> Void = {}
    private let menu = NSMenu()

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            let x = item.button.map { $0.convert(event?.locationInWindow ?? .zero, from: nil).x } ?? 0
            open(x > 5 && x < 17 ? "com.apple.wifi-settings-extension" : "com.apple.Battery-Settings.extension")
        }
    }

    @objc private func settingsClicked() { openSettings() }

    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
    }

    private func signal() -> Double {
        guard let rssi = CWWiFiClient.shared().interface()?.rssiValue(), rssi != 0 else { return -1 }
        return rssi > -55 ? 1 : rssi > -65 ? 0.66 : rssi > -75 ? 0.33 : 0.1
    }

    private func power() -> (percent: Int, plugged: Bool, charging: Bool) {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        guard let source = list.first,
              let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { return (0, false, false) }
        return (desc[kIOPSCurrentCapacityKey] as? Int ?? 0, desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                desc[kIOPSIsChargingKey] as? Bool ?? false)
    }

    private func refresh() {
        let (percent, plugged, charging) = power(), level = signal()
        let saver = ProcessInfo.processInfo.isLowPowerModeEnabled
        let key = "\(percent)-\(level)-\(charging)-\(plugged)-\(saver)"
        guard key != last else { return }
        last = key
        item.button?.image = draw(percent: percent, level: level, charging: charging, plugged: plugged, saver: saver)
    }

    private func draw(percent: Int, level: Double, charging: Bool, plugged: Bool, saver: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            let center = NSPoint(x: 11, y: 11.5), radius: CGFloat = 8.3
            let accent: NSColor = saver ? .systemYellow : .labelColor
            func arc(_ to: CGFloat, color: NSColor) {
                let path = NSBezierPath()
                path.appendArc(withCenter: center, radius: radius, startAngle: 225, endAngle: to, clockwise: true)
                path.lineWidth = 2.0
                path.lineCapStyle = .round
                color.setStroke()
                path.stroke()
            }
            arc(-45, color: NSColor.labelColor.withAlphaComponent(0.3))
            if percent > 0 { arc(225 - 270 * CGFloat(min(percent, 100)) / 100, color: accent) }

            let name = level < 0 ? "wifi.slash" : "wifi"
            let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .heavy)
            let base = level < 0 ? NSImage(systemSymbolName: name, accessibilityDescription: nil)
                                 : NSImage(systemSymbolName: name, variableValue: level, accessibilityDescription: nil)
            if let symbol = base?.withSymbolConfiguration(config.applying(.init(paletteColors: [.labelColor]))) {
                let size = symbol.size
                symbol.draw(in: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2 + 0.5, width: size.width, height: size.height))
            }

            if let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 7.8, weight: .bold).applying(.init(paletteColors: [plugged ? .labelColor : NSColor.labelColor.withAlphaComponent(0.5)]))) {
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: center.x, yBy: 3.5)
                transform.rotate(byDegrees: 90)
                transform.concat()
                bolt.draw(in: NSRect(x: -bolt.size.width / 2, y: -bolt.size.height / 2, width: bolt.size.width, height: bolt.size.height))
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        return image
    }
}

final class WifiEvents: NSObject, CWEventDelegate {
    var onChange: () -> Void = {}
    func linkQualityDidChangeForWiFiInterface(withName interfaceName: String, rssi: Int, transmitRate: Double) { onChange() }
    func ssidDidChangeForWiFiInterface(withName interfaceName: String) { onChange() }
    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) { onChange() }
}
