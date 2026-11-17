import AppKit
import ApplicationServices

/// Esconde o aviso nativo de "Conectado" do macOS (o painel do Bluetooth) para sobrar só o da ilha.
@MainActor
final class NativePopupGuard {
    private var handled = Set<Int>()
    private let ignored: Set<String> = ["Ilha", "Window Server", "ControlCenter", "SystemUIServer", "Dock", "MenuBarAgent",
                                        "NotificationCenter", "Finder", "WindowManager", "Terminal", "Ajustes do Sistema"]

    func start() {
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
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
                  y < 160, width < 600, height < 140, !ignored.contains(owner), !handled.contains(id) else { continue }
            handled.insert(id)
            log("janela nova: \(owner) id=\(id) layer=\(layer) \(bounds)")
            guard owner.localizedCaseInsensitiveContains("bluetooth") else { continue }
            let hidden = hide(pid: pid)
            log("bluetooth popup escondido=\(hidden)")
        }
    }

    private func hide(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var value: AnyObject?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard let windows = value as? [AXUIElement], !windows.isEmpty else { return false }
        var moved = false
        for window in windows {
            var point = CGPoint(x: -5000, y: -5000)
            if let position = AXValueCreate(.cgPoint, &point),
               AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success { moved = true }
        }
        return moved
    }
}
