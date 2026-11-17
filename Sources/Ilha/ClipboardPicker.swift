import AppKit
import SwiftUI

@MainActor
final class PickerModel: ObservableObject {
    @Published var selected = 0
}

/// Seletor flutuante da área de transferência, aberto junto do mouse (⌥ X) em qualquer tela.
@MainActor
final class ClipboardPicker {
    private let store: ClipboardStore
    private let model = PickerModel()
    private var panel: NSPanel?
    private var clickMonitor: Any?

    var isVisible: Bool { panel?.isVisible == true }

    init(store: ClipboardStore) { self.store = store }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        model.selected = 0
        let rows = max(1, min(store.items.count, 5))
        let size = CGSize(width: 340, height: store.items.isEmpty ? 84 : CGFloat(40 + rows * 34 + 10))
        let view = ClipboardPickerView(store: store, model: model) { [weak self] index in self?.choose(index) }
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: view)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        var origin = NSPoint(x: mouse.x + 10, y: mouse.y - size.height - 10)
        origin.x = min(max(origin.x, area.minX + 8), area.maxX - size.width - 8)
        origin.y = min(max(origin.y, area.minY + 8), area.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        self.panel = panel

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func choose(_ index: Int) {
        guard store.items.indices.contains(index) else { return }
        store.copy(store.items[index])
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { Self.paste() }
    }

    /// Cola no app em foco: o seletor não ativa a Ilha, então o foco continua onde estava.
    private static func paste() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Teclas enquanto o seletor está aberto: 1–5, setas, Return e Esc. Devolve se a tecla foi usada.
    func handleKey(_ code: Int64) -> Bool {
        guard isVisible else { return false }
        switch code {
        case 53: hide()
        case 18, 19, 20, 21, 23: choose([18: 0, 19: 1, 20: 2, 21: 3, 23: 4][code] ?? 0)
        case 83, 84, 85, 86, 87: choose(Int(code) - 83)
        case 126: model.selected = max(0, model.selected - 1)
        case 125: model.selected = min(max(store.items.count - 1, 0), model.selected + 1)
        case 36, 76: choose(model.selected)
        default: return false
        }
        return true
    }
}

struct ClipboardPickerView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var model: PickerModel
    var choose: (Int) -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Área de transferência").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("1–5 cola · esc").font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
            }
            .frame(height: 26)
            if store.items.isEmpty {
                Spacer()
                Text("Nada copiado ainda").font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                Spacer()
            } else {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in row(index, item) }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))
    }

    private func row(_ index: Int, _ item: ClipItem) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)").font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5)).frame(width: 12)
            if let image = store.thumbnail(for: item) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 4))
                Text("Imagem \(item.imageSize ?? "")").font(.system(size: 12)).lineLimit(1)
            } else {
                Text((item.text ?? "").replacingOccurrences(of: "\n", with: " ")).font(.system(size: 12)).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(item.date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(model.selected == index ? 0.2 : 0.07)))
        .contentShape(Rectangle())
        .onTapGesture { choose(index) }
    }
}
