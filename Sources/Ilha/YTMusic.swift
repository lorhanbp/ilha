import AppKit
import ApplicationServices

/// Player favorito: o web app do YouTube Music é controlado pela Acessibilidade, sem trazê-lo pra frente; Spotify e Música, por AppleScript.
enum YTMusic {
    static let defaultPath = NSHomeDirectory() + "/Applications/YT Music.app"
    static var appURL: URL {
        URL(fileURLWithPath: UserDefaults.standard.string(forKey: "favoritePlayerPath") ?? defaultPath)
    }
    static var bundleID: String? { Bundle(url: appURL)?.bundleIdentifier }
    static var exists: Bool { FileManager.default.fileExists(atPath: appURL.path) }
    private static var isWebApp: Bool { bundleID?.hasPrefix("com.apple.Safari.WebApp") == true }
    private static let playTitles: Set<String> = ["Tocar", "Reproduzir", "Play"]
    private static let titles: [String: Set<String>] = [
        "toggle": ["Tocar", "Pausar", "Reproduzir", "Play", "Pause"],
        "next": ["Avançar", "Próxima", "Next"],
        "prev": ["Anterior", "Voltar", "Previous"],
    ]

    private static func runningPID() -> pid_t? {
        let id = Bundle(url: appURL)?.bundleIdentifier
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.standardizedFileURL == appURL.standardizedFileURL
                || (id != nil && $0.bundleIdentifier == id) || $0.localizedName == "YT Music"
        }?.processIdentifier
    }

    /// Abre o web app em segundo plano, se preciso, e aperta o botão de tocar.
    static func resume() async {
        guard exists else { return }
        if !isWebApp {
            if let id = bundleID, ["com.spotify.client", "com.apple.Music"].contains(id) {
                NSAppleScript(source: "tell application id \"\(id)\" to play")?.executeAndReturnError(nil)
            } else {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            }
            return
        }
        if runningPID() == nil {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
        for _ in 0..<20 {
            if let pid = runningPID(), pressPlay(pid) { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    /// O macOS segura a janela escondida no canto de baixo à esquerda, só uns 44×40 px dela aparecem.
    private static let hidden = CGPoint(x: -4000, y: 5000)

    private static func windows(_ pid: pid_t) -> [AXUIElement] {
        (attribute(AXUIElementCreateApplication(pid), "AXWindows") as? [AXUIElement]) ?? []
    }

    private static func move(_ pid: pid_t, to point: CGPoint) {
        for window in windows(pid) {
            var target = point
            if let value = AXValueCreate(.cgPoint, &target) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            }
        }
    }

    private static func isOnScreen(_ pid: pid_t) -> Bool {
        guard let window = windows(pid).first, let value = attribute(window, "AXPosition") else { return false }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point.x > -1000
    }

    /// Traz a janela de volta pra tela (ela fica escondida fora dela depois de um pulo) e a ativa.
    static func showWindow() async {
        guard let pid = runningPID() else { return }
        move(pid, to: CGPoint(x: 120, y: 120))
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    /// Pula `delta` segundos com as teclas J/L (10 s cada). Só elas pulam, e só com o app em foco:
    /// a janela fica escondida fora da tela, então ativar o app não mostra nada além de uma faixa na borda.
    static func seek(by delta: Double) async {
        let presses = min(40, Int((abs(delta) / 10).rounded()))
        guard presses > 0, let pid = runningPID() else { return }
        let previous = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        let alreadyFront = previous?.processIdentifier == pid
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if !alreadyFront {
            if isOnScreen(pid) { move(pid, to: hidden) }
            _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            try? await Task.sleep(nanoseconds: 450_000_000)
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<presses {
            for down in [true, false] {
                CGEvent(keyboardEventSource: source, virtualKey: delta > 0 ? 37 : 38, keyDown: down)?.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        if !alreadyFront, let previous, let url = previous.bundleURL {
            try? await Task.sleep(nanoseconds: 100_000_000)
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    }

    /// Aperta o botão do player (toggle, next, prev). Falso se o web app não está aberto.
    static func control(_ command: String) -> Bool {
        guard let wanted = titles[command], let pid = runningPID() else { return false }
        return press(pid, wanted)
    }

    private static func pressPlay(_ pid: pid_t) -> Bool { press(pid, playTitles) }

    private static func press(_ pid: pid_t, _ wanted: Set<String>) -> Bool {
        let root = AXUIElementCreateApplication(pid)
        guard let toolbar = find(root, maxDepth: 40, { role($0) == "AXToolbar" && title($0) == "Barra do player" }),
              let button = find(toolbar, maxDepth: 12, { role($0) == "AXButton" && wanted.contains(title($0)) })
        else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value
    }

    private static func role(_ element: AXUIElement) -> String { attribute(element, "AXRole") as? String ?? "" }

    private static func title(_ element: AXUIElement) -> String {
        (attribute(element, "AXTitle") as? String) ?? (attribute(element, "AXDescription") as? String) ?? ""
    }

    private static func find(_ element: AXUIElement, maxDepth: Int, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
        if match(element) { return element }
        guard maxDepth > 0 else { return nil }
        for child in (attribute(element, "AXChildren") as? [AXUIElement]) ?? [] {
            if let found = find(child, maxDepth: maxDepth - 1, match) { return found }
        }
        return nil
    }
}
