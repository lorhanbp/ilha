import AppKit
import ApplicationServices

/// Esconde o aviso nativo de "Conectado" do macOS (o painel do Bluetooth) para sobrar só o da ilha.
@MainActor
final class NativePopupGuard {
    private var handled = Set<Int>()
    private let ignored: Set<String> = ["Ilha", "Window Server", "ControlCenter", "SystemUIServer", "Dock", "MenuBarAgent",
                                        "NotificationCenter", "Finder", "WindowManager", "Terminal", "Ajustes do Sistema"]

    var onPopupOpened: () -> Void = {}
    var onPopupClosed: () -> Void = {}
    private var observer: AXObserver?
    private var watchedPID: pid_t = 0

    /// Pede ao macOS para avisar no instante em que o MenuBarAgent cria uma janela, antes de ela aparecer na tela.
    func watch() {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.lastPathComponent == "MenuBarAgent.app" }),
              app.processIdentifier != watchedPID else { return }
        let callback: AXObserverCallback = { _, element, notification, context in
            guard let context else { return }
            let popupGuard = Unmanaged<NativePopupGuard>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if (notification as String) == kAXUIElementDestroyedNotification { popupGuard.popupClosed(element) } else { popupGuard.windowCreated(element) }
            }
        }
        var created: AXObserver?
        guard AXObserverCreate(app.processIdentifier, callback, &created) == .success, let created else { return }
        AXObserverAddNotification(created, AXUIElementCreateApplication(app.processIdentifier), kAXWindowCreatedNotification as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        watchedPID = app.processIdentifier
    }

    private func popupClosed(_ window: AXUIElement) {
        if let observer { AXObserverRemoveNotification(observer, window, kAXUIElementDestroyedNotification as CFString) }
        onPopupClosed()
    }

    private func windowCreated(_ window: AXUIElement) {
        var raw: AnyObject?
        var size = CGSize.zero
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &raw)
        if let raw, AXValueGetValue(raw as! AXValue, .cgSize, &size), abs(size.width - 367) < 2, abs(size.height - 154) < 2 {
            var point = CGPoint(x: -5000, y: -5000)
            if let position = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) }
            if let observer { AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, Unmanaged.passUnretained(self).toOpaque()) }
            onPopupOpened()
        } else {
            burst()
        }
    }

    /// Varredura rápida logo depois de um aparelho conectar, que é quando o aviso nativo aparece.
    func burst() {
        watch()
        var left = 150
        Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] timer in
            Task { @MainActor in self?.scan() }
            left -= 1
            if left <= 0 { timer.invalidate() }
        }
    }

    private func log(_ text: String) {
        let line = "\(Date()) \(text)\n"
        if let handle = FileHandle(forWritingAtPath: "/tmp/ilha.log") {
            handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
        }
    }

    private func scan() {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return }
        for window in windows {
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  let id = window[kCGWindowNumber as String] as? Int,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let layer = window[kCGWindowLayer as String] as? Int, layer > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Double],
                  let y = bounds["Y"], let width = bounds["Width"], let height = bounds["Height"],
                  y < 160, width < 600 else { continue }
            // Hoje o aviso de conectado/desconectado é uma janela do MenuBarAgent (367x154, logo abaixo da barra).
            if owner == "MenuBarAgent" {
                guard width > 300, width < 450, height > 100, height < 200 else { continue }
                guard y > 0 else { continue }
                let moved = hide(pid: pid, onlySize: CGSize(width: width, height: height))
                if handled.insert(id).inserted { log("popup do MenuBarAgent movido=\(moved) id=\(id) \(bounds)") }
                continue
            }
            guard height < 140, !ignored.contains(owner), !handled.contains(id) else { continue }
            handled.insert(id)
            log("janela nova: \(owner) id=\(id) layer=\(layer) \(bounds)")
            guard owner.localizedCaseInsensitiveContains("bluetooth") else { continue }
            let hidden = hide(pid: pid)
            log("bluetooth popup escondido=\(hidden)")
        }
    }

    private func hide(pid: pid_t, onlySize: CGSize? = nil) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var value: AnyObject?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard let windows = value as? [AXUIElement], !windows.isEmpty else { return false }
        var moved = false
        for window in windows {
            if let onlySize {
                var raw: AnyObject?
                var size = CGSize.zero
                AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &raw)
                guard let raw, AXValueGetValue(raw as! AXValue, .cgSize, &size),
                      abs(size.width - onlySize.width) < 2, abs(size.height - onlySize.height) < 2 else { continue }
            }
            var point = CGPoint(x: -5000, y: -5000)
            if let position = AXValueCreate(.cgPoint, &point),
               AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success { moved = true }
        }
        return moved
    }
}
