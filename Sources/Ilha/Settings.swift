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
        launchAtLogin = SMAppService.mainApp.status == .enabled
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
            group("Proteção do ⌘Q") {
                Toggle("Segurar ⌘Q para fechar (Claude, Terminal, Safari, Grok Bot e Cursor)", isOn: $settings.quitHoldEnabled)
                HStack {
                    Text("Tempo: \(String(format: "%.1f", settings.quitHoldSeconds)) s")
                    Slider(value: $settings.quitHoldSeconds, in: 0.5...3, step: 0.1)
                }
                .disabled(!settings.quitHoldEnabled)
            }
            group("Geral") {
                Toggle("Abrir ao ligar o Mac", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
            }
            Spacer(minLength: 0)
            Text("Ilha · github.com/lorhanbp/ilha").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 460, height: 400)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }
}
