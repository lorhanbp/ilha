import AppKit
import ServiceManagement
import SwiftUI

/// Ajustes básicos, guardados em UserDefaults.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var shortcutKeyCode: Int { didSet { defaults.set(shortcutKeyCode, forKey: "shortcutKeyCode") } }
    @Published var shortcutModifiers: UInt64 { didSet { defaults.set(shortcutModifiers, forKey: "shortcutModifiers") } }
    @Published var shortcutLabel: String { didSet { defaults.set(shortcutLabel, forKey: "shortcutLabel") } }
    @Published var clipboardLimit: Int { didSet { defaults.set(clipboardLimit, forKey: "clipboardLimit") } }
    @Published var clipboardHours: Int { didSet { defaults.set(clipboardHours, forKey: "clipboardHours") } }
    @Published var quitHoldEnabled: Bool { didSet { defaults.set(quitHoldEnabled, forKey: "quitHoldEnabled") } }
    @Published var quitHoldSeconds: Double { didSet { defaults.set(quitHoldSeconds, forKey: "quitHoldSeconds") } }
    @Published var protectedApps: [String] { didSet { defaults.set(protectedApps, forKey: "protectedApps") } }
    @Published var favoritePlayerPath: String { didSet { defaults.set(favoritePlayerPath, forKey: "favoritePlayerPath") } }
    @Published var recording = false
    @Published var launchAtLogin: Bool

    static let relevantFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    private init() {
        func int(_ key: String, _ fallback: Int) -> Int { UserDefaults.standard.object(forKey: key) as? Int ?? fallback }
        shortcutKeyCode = int("shortcutKeyCode", 7)
        shortcutModifiers = UserDefaults.standard.object(forKey: "shortcutModifiers") as? UInt64 ?? CGEventFlags.maskAlternate.rawValue
        shortcutLabel = UserDefaults.standard.string(forKey: "shortcutLabel") ?? "X"
        clipboardLimit = int("clipboardLimit", 5)
        clipboardHours = int("clipboardHours", 24)
        quitHoldEnabled = UserDefaults.standard.object(forKey: "quitHoldEnabled") as? Bool ?? true
        quitHoldSeconds = UserDefaults.standard.object(forKey: "quitHoldSeconds") as? Double ?? 1.2
        protectedApps = UserDefaults.standard.stringArray(forKey: "protectedApps") ?? [
            "com.anthropic.claudefordesktop", "com.apple.Terminal", "com.apple.Safari",
            "com.anysphere.sand", "com.todesktop.230313mzl4w4u92"]
        let saved = UserDefaults.standard.string(forKey: "favoritePlayerPath")
        favoritePlayerPath = saved ?? (FileManager.default.fileExists(atPath: YTMusic.defaultPath) ? YTMusic.defaultPath : "")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Players que a Ilha sabe retomar e que estão instalados.
    var playerCandidates: [String] {
        var paths = ["/Applications/Spotify.app", "/System/Applications/Music.app", "/Applications/Music.app"]
        let user = NSHomeDirectory() + "/Applications"
        for name in (try? FileManager.default.contentsOfDirectory(atPath: user)) ?? [] where name.hasSuffix(".app") {
            if Bundle(path: user + "/" + name)?.bundleIdentifier?.hasPrefix("com.apple.Safari.WebApp") == true { paths.append(user + "/" + name) }
        }
        return paths.filter { FileManager.default.fileExists(atPath: $0) }
    }

    func choosePlayer() {
        let panel = NSOpenPanel()
        panel.title = "Escolha o app de música"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        if panel.runModal() == .OK, let url = panel.url { favoritePlayerPath = url.path }
    }

    func playerName(_ path: String) -> String {
        path.isEmpty ? "Nenhum" : FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }

    func addProtectedApp() {
        let panel = NSOpenPanel()
        panel.title = "Escolha o app"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !protectedApps.contains(id) { protectedApps.append(id) }
        }
    }

    func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    func appIcon(_ bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    var shortcutDescription: String {
        let flags = CGEventFlags(rawValue: shortcutModifiers)
        var text = ""
        if flags.contains(.maskControl) { text += "⌃" }
        if flags.contains(.maskAlternate) { text += "⌥" }
        if flags.contains(.maskShift) { text += "⇧" }
        if flags.contains(.maskCommand) { text += "⌘" }
        return text + shortcutLabel
    }

    func matches(code: Int64, flags: CGEventFlags) -> Bool {
        Int(code) == shortcutKeyCode && flags.intersection(Self.relevantFlags).rawValue == shortcutModifiers
    }

    func setShortcut(code: Int64, flags: CGEventFlags, label: String) {
        shortcutKeyCode = Int(code)
        shortcutModifiers = flags.intersection(Self.relevantFlags).rawValue
        shortcutLabel = label.uppercased()
        recording = false
    }

    func resetShortcut() {
        shortcutKeyCode = 7
        shortcutModifiers = CGEventFlags.maskAlternate.rawValue
        shortcutLabel = "X"
        recording = false
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("Área de transferência") {
                HStack {
                    Text("Atalho")
                    Spacer()
                    Text(settings.recording ? "Pressione as teclas…" : settings.shortcutDescription)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                    Button(settings.recording ? "Cancelar" : "Gravar") { settings.recording.toggle() }
                    Button("Padrão") { settings.resetShortcut() }
                }
                Stepper("Itens guardados: \(settings.clipboardLimit)", value: $settings.clipboardLimit, in: 1...9)
                Stepper("Apagar depois de \(settings.clipboardHours) h", value: $settings.clipboardHours, in: 1...72)
                Text("Com o atalho, o seletor abre junto do mouse. Escolha com os números, as setas e Return, ou clique: o item é colado no app em foco.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            group("Música") {
                HStack {
                    Text("App favorito")
                    Spacer()
                    if !settings.favoritePlayerPath.isEmpty {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: settings.favoritePlayerPath)).resizable().frame(width: 20, height: 20)
                    }
                    Text(settings.playerName(settings.favoritePlayerPath))
                    Menu("Escolher") {
                        ForEach(settings.playerCandidates, id: \.self) { path in
                            Button(settings.playerName(path)) { settings.favoritePlayerPath = path }
                        }
                        Divider()
                        Button("Outro…") { settings.choosePlayer() }
                        Button("Nenhum") { settings.favoritePlayerPath = "" }
                    }
                    .fixedSize()
                }
                Text("É o app que o F8 retoma quando o macOS esquece o player. Spotify e Música voltam a tocar por AppleScript (o macOS pede permissão na primeira vez); o web app do YouTube Music é controlado pela Acessibilidade.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            group("Proteção do ⌘Q") {
                Toggle("Segurar ⌘Q para fechar os apps da lista", isOn: $settings.quitHoldEnabled)
                HStack {
                    Text("Tempo: \(String(format: "%.1f", settings.quitHoldSeconds)) s")
                    Slider(value: $settings.quitHoldSeconds, in: 0.5...3, step: 0.1)
                }
                .disabled(!settings.quitHoldEnabled)
                VStack(spacing: 4) {
                    ForEach(settings.protectedApps, id: \.self) { id in
                        HStack(spacing: 8) {
                            if let icon = settings.appIcon(id) { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                            Text(settings.appName(id)).lineLimit(1)
                            Spacer()
                            Button { settings.protectedApps.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                        }
                    }
                    if settings.protectedApps.isEmpty {
                        Text("Nenhum app na lista.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Button("Adicionar app…") { settings.addProtectedApp() }
                    .disabled(!settings.quitHoldEnabled)
            }
            group("Geral") {
                Toggle("Abrir ao ligar o Mac", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
            }
            Spacer(minLength: 0)
            Text("Ilha · github.com/lorhanbp/ilha").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 460, height: 610)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }
}
