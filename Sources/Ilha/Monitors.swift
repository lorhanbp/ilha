import AppKit
import Foundation

@MainActor
final class HUDModel: ObservableObject {
    enum Kind { case volume, brightness, accessory, quit, battery }
    @Published var visible = false
    private(set) var kind = Kind.volume
    private(set) var level: Float = 0
    private(set) var muted = false
    private(set) var symbol = ""
    private(set) var text = ""
    private(set) var quitStart = Date()
    private(set) var quitSeconds = 1.2
    private var hideTask: Task<Void, Never>?

    func show(_ kind: Kind, level: Float, muted: Bool = false) {
        present(kind, level: level, muted: muted, symbol: "", text: "", seconds: 1.4)
    }

    func showAccessory(symbol: String, text: String) {
        present(.accessory, level: 0, muted: false, symbol: symbol, text: text, seconds: 3)
    }

    /// Largura de cada lado do notch enquanto o aviso está na tela: o texto longo ("Desconectado") não pode entrar atrás do notch.
    var wing: CGFloat {
        guard kind == .accessory else { return 74 }
        let width = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: .semibold)]).width
        return max(74, ceil(width) + 26)
    }

    func showBattery(percent: Int, charging: Bool) {
        present(.battery, level: Float(percent) / 100, muted: charging, symbol: "", text: "\(percent)%", seconds: 2.5)
    }

    func showQuit(seconds: Double) {
        quitStart = Date()
        quitSeconds = seconds
        present(.quit, level: 0, muted: false, symbol: "", text: "", seconds: seconds + 1)
    }

    private var holding = false

    /// O aviso do macOS (escondido) ainda estaria aberto: a ilha segura o aviso de acessório até ele fechar.
    func hold() {
        holding = true
        guard visible, kind == .accessory else { return }
        keepUntil(seconds: 8)
    }

    /// O macOS fechou o aviso: a ilha espera mais 2 segundos e fecha.
    func release() {
        holding = false
        guard visible, kind == .accessory else { return }
        keepUntil(seconds: 2)
    }

    private func keepUntil(seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled { self?.visible = false }
        }
    }

    func hide() {
        hideTask?.cancel()
        visible = false
    }

    private func present(_ kind: Kind, level: Float, muted: Bool, symbol: String, text: String, seconds: Double) {
        self.kind = kind
        self.level = level
        self.muted = muted
        self.symbol = symbol
        self.text = text
        visible = true
        objectWillChange.send()
        keepUntil(seconds: kind == .accessory && holding ? 8 : seconds)
    }
}
