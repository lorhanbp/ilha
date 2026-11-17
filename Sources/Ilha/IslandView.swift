import AppKit
import SwiftUI

enum IslandTab { case music, clipboard, energy, system }

@MainActor
final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var tab = IslandTab.music
    var expandedHeight: CGFloat {
        switch tab {
        case .music: return 128
        case .clipboard: return 192
        case .energy: return 206
        case .system: return 194
        }
    }
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    init(notchWidth: CGFloat, notchHeight: CGFloat) {
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
    }
}

enum IslandLayout {
    static let expandedSize = CGSize(width: 340, height: 210)

    static func wing(hasTrack: Bool, hud: Bool) -> CGFloat {
        if hud { return 74 }
        return hasTrack ? 38 : 0
    }
}

struct BatteryRing: View {
    var percent: Int
    var charging: Bool
    var size: CGFloat
    var lineWidth: CGFloat
    var showsText = true
    var symbol: String?
    var tint: Color?

    private var color: Color { tint ?? (percent <= 20 && !charging ? .red : .green) }

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: lineWidth)
            Circle().trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let symbol {
                Image(systemName: symbol).font(.system(size: size * 0.42)).foregroundStyle(.white.opacity(0.85))
            } else if showsText {
                Text("\(percent)").font(.system(size: size * 0.3, weight: .bold).monospacedDigit()).foregroundStyle(.white)
            } else if charging {
                Image(systemName: "bolt.fill").font(.system(size: size * 0.45)).foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Vidro fosco igual ao dos menus do macOS.
struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct GlassBackground: View {
    var radius: CGFloat

    var body: some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
        ZStack {
            VisualEffect().clipShape(shape)
            shape.fill(LinearGradient(stops: [.init(color: .black, location: 0),
                                              .init(color: .black.opacity(0.75), location: 0.22),
                                              .init(color: .black.opacity(0.0), location: 0.6)],
                                      startPoint: .top, endPoint: .bottom))
        }
    }
}

struct Equalizer: View {
    var playing: Bool
    var height: CGFloat
    private static let idle: [Double] = [0.4, 0.4, 0.4, 0.4, 0.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 1.5) {
                ForEach(0..<5, id: \.self) { i in
                    let level = playing ? 0.25 + 0.75 * abs(sin(t * (3.2 + Double(i) * 0.9) + Double(i))) : Self.idle[i]
                    Capsule().fill(.white).frame(width: 2, height: height * level)
                }
            }
            .frame(height: height)
        }
    }
}

struct IslandView: View {
    @ObservedObject var music: MusicModel
    @ObservedObject var state: IslandState
    @ObservedObject var hud: HUDModel
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var energy: EnergyModel
    @ObservedObject var accessories: AccessoryMonitor
    @ObservedObject var system: SystemMonitor
    var body: some View {
        let wing = IslandLayout.wing(hasTrack: music.hasTrack, hud: hud.visible)
        let width = state.expanded ? IslandLayout.expandedSize.width : state.notchWidth + wing * 2
        let height = state.expanded ? state.expandedHeight : state.notchHeight
        let radius: CGFloat = state.expanded ? 22 : 14

        ZStack(alignment: .top) {
            if state.expanded { GlassBackground(radius: radius) } else {
                UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius).fill(.black)
            }
            if state.expanded { expandedContainer }
            else if hud.visible { hudContent }
            else if wing > 0 { compactContent }
        }
        .frame(width: width, height: height)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius))
        .animation(state.expanded ? .spring(response: 0.38, dampingFraction: 0.8) : .spring(response: 0.2, dampingFraction: 0.92),
                   value: state.expanded)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: state.tab)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: wing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var cover: some View {
        Group {
            if let image = music.cover {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.white.opacity(0.12)
            }
        }
    }

    private var compactContent: some View {
        let side = state.notchHeight - 12
        return HStack(spacing: 0) {
            cover.frame(width: side, height: side).clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(.leading, 7)
            Spacer(minLength: state.notchWidth)
            Equalizer(playing: music.playing, height: state.notchHeight - 22)
                .padding(.trailing, 9)
        }
        .frame(height: state.notchHeight)
    }

    private var hudContent: some View {
        if hud.kind == .battery {
            return AnyView(HStack(spacing: 0) {
                BatteryRing(percent: Int(hud.level * 100), charging: hud.muted, size: 22, lineWidth: 2.5,
                            symbol: hud.muted ? "battery.100.bolt" : "battery.100")
                    .frame(width: 30, alignment: .leading).padding(.leading, 14)
                Spacer(minLength: state.notchWidth)
                Text(hud.text).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                    .padding(.trailing, 14)
            }.frame(height: state.notchHeight))
        }
        if hud.kind == .quit {
            return AnyView(HStack(spacing: 0) {
                Image(systemName: "power").font(.system(size: 13)).foregroundStyle(.red)
                    .frame(width: 30, alignment: .leading).padding(.leading, 14)
                Spacer(minLength: state.notchWidth)
                TimelineView(.animation) { context in
                    let progress = min(1, max(0, context.date.timeIntervalSince(hud.quitStart) / hud.quitSeconds))
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(.white).frame(width: 46 * progress)
                    }
                    .frame(width: 46, height: 4)
                }
                .padding(.trailing, 14)
            }.frame(height: state.notchHeight))
        }
        if hud.kind == .accessory {
            return AnyView(HStack(spacing: 0) {
                Image(systemName: hud.symbol).font(.system(size: 13)).foregroundStyle(.white)
                    .frame(width: 30, alignment: .leading).padding(.leading, 14)
                Spacer(minLength: state.notchWidth)
                Text(hud.text).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.8).padding(.trailing, 10)
            }.frame(height: state.notchHeight))
        }
        let symbol: String = {
            if hud.kind == .brightness { return "sun.max.fill" }
            if hud.muted || hud.level == 0 { return "speaker.slash.fill" }
            return hud.level < 0.34 ? "speaker.wave.1.fill" : hud.level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        }()
        return AnyView(HStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .frame(width: 30, alignment: .leading)
                .padding(.leading, 14)
            Spacer(minLength: state.notchWidth)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white).frame(width: 46 * CGFloat(hud.muted ? 0 : hud.level))
            }
            .frame(width: 46, height: 4)
            .padding(.trailing, 14)
        }
        .frame(height: state.notchHeight))
    }

    private var expandedContainer: some View {
        ZStack(alignment: .top) {
            switch state.tab {
            case .music: expandedContent
            case .clipboard: clipboardContent
            case .energy: energyContent
            case .system: systemContent
            }
            HStack {
                HStack(spacing: 2) {
                    tabButton("music.note", .music)
                    tabButton("bolt.fill", .energy)
                }
                Spacer(minLength: state.notchWidth)
                HStack(spacing: 2) {
                    tabButton("cpu", .system)
                    tabButton("doc.on.clipboard", .clipboard)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: state.notchHeight)
        }
    }

    private func tabButton(_ symbol: String, _ tab: IslandTab) -> some View {
        Button { state.tab = tab } label: {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(state.tab == tab ? .white : .white.opacity(0.35))
                .frame(width: 28, height: 22)
        }
        .buttonStyle(.plain)
    }

    private func loadColor(_ percent: Int) -> Color { percent < 60 ? .green : percent < 85 ? .orange : .red }

    private func loadRow(_ symbol: String, _ title: String, percent: Int, value: String) -> some View {
        HStack(spacing: 8) {
            BatteryRing(percent: percent, charging: false, size: 22, lineWidth: 2.5, symbol: symbol, tint: loadColor(percent))
                .frame(width: 22)
            Text(title).font(.system(size: 12))
            Spacer(minLength: 4)
            Text(value).font(.system(size: 12, weight: .semibold).monospacedDigit())
        }
        .frame(height: 24)
    }

    private func temperatureColor(_ value: Int) -> Color { value < 60 ? .green : value < 80 ? .orange : .red }

    private var systemContent: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: state.notchHeight - 4)
            loadRow("cpu", "CPU", percent: system.cpu, value: "\(system.cpu)%")
            loadRow("memorychip", "RAM", percent: system.memoryPercent,
                    value: String(format: "%.1f de %.0f GB", system.memoryUsedGB, system.memoryTotalGB))
            loadRow("display", "GPU", percent: system.gpu ?? 0, value: system.gpu.map { "\($0)%" } ?? "–")
            loadRow("internaldrive", "SSD", percent: system.storagePercent,
                    value: String(format: "%.0f de %.0f GB", system.storageUsedGB, system.storageTotalGB))
            if let cpuTemperature = system.cpuTemperature {
                HStack(spacing: 8) {
                    BatteryRing(percent: min(cpuTemperature, 100), charging: false, size: 22, lineWidth: 2.5,
                                symbol: "thermometer.medium", tint: temperatureColor(cpuTemperature))
                        .frame(width: 22)
                    Text("Temperatura").font(.system(size: 12))
                    if let battery = system.batteryTemperature {
                        Text("bateria \(battery)°").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer(minLength: 4)
                    Text("\(cpuTemperature)°C").font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
                .frame(height: 24)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var energyContent: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: state.notchHeight - 4)
            HStack(spacing: 8) {
                BatteryRing(percent: energy.percent, charging: energy.charging, size: 22, lineWidth: 2.5,
                            symbol: energy.charging ? "battery.100.bolt" : "battery.100")
                    .frame(width: 22)
                Text(energy.charging ? "Carregando" : energy.plugged ? "Na tomada" : "Na bateria").font(.system(size: 12))
                if let minutes = energy.minutes {
                    Text("\(minutes / 60) h \(minutes % 60) min").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 4)
                Text("\(energy.percent)%").font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
            .frame(height: 24)
            energyRow("bolt.fill", "Sistema", energy.systemWatts.map { String(format: "%.0f W", $0) } ?? "–", .orange)
            if energy.plugged {
                let volts = energy.adapterVolts.map { String(format: "%.1f V", $0) } ?? ""
                let usage = energy.adapterInWatts.map { String(format: "%.0f", $0) } ?? "–"
                energyRow("powerplug.fill", "Adaptador", "\(usage) de \(energy.adapterRated ?? 0) W", .blue, detail: volts)
            }
            energyRow("heart.fill", "Saúde", energy.health.map { "\($0)%" } ?? "–", .pink,
                      detail: energy.cycles.map { "\($0) ciclos" } ?? "")
            if !accessories.devices.isEmpty {
                Divider().overlay(.white.opacity(0.1))
                ForEach(accessories.devices.prefix(2)) { device in
                    HStack(spacing: 8) {
                        BatteryRing(percent: device.level ?? 0, charging: false, size: 22, lineWidth: 2.5, symbol: device.symbol)
                            .frame(width: 22)
                        Text(device.displayName).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(device.battery ?? "–").font(.system(size: 12, weight: .semibold).monospacedDigit())
                    }
                    .frame(height: 24)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private func energyRow(_ symbol: String, _ title: String, _ value: String, _ tint: Color, detail: String = "") -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(tint).frame(width: 20)
            Text(title).font(.system(size: 12)).lineLimit(1)
            if !detail.isEmpty { Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1) }
            Spacer(minLength: 4)
            Text(value).font(.system(size: 12, weight: .semibold).monospacedDigit())
        }
        .frame(height: 20)
    }

    private var clipboardContent: some View {
        VStack(spacing: 4) {
            Spacer().frame(height: state.notchHeight - 6)
            HStack {
                Text("Área de transferência").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                if !clipboard.items.isEmpty {
                    Button("Limpar") { clipboard.clear() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }
            if clipboard.items.isEmpty {
                Spacer()
                Text("Nada copiado ainda").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                Spacer()
            } else {
                ForEach(clipboard.items) { item in clipRow(item) }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func clipRow(_ item: ClipItem) -> some View {
        HStack(spacing: 8) {
            if let image = clipboard.thumbnail(for: item) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 18, height: 18).clipShape(RoundedRectangle(cornerRadius: 4))
                Text("Imagem \(item.imageSize ?? "")").font(.system(size: 12)).lineLimit(1)
            } else {
                Image(systemName: "text.alignleft").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    .frame(width: 22)
                Text((item.text ?? "").replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 12)).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(clipboard.copiedID == item.id ? "Copiado" : item.date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.1)))
        .contentShape(Rectangle())
        .onTapGesture { clipboard.copy(item) }
    }

    private var expandedContent: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: state.notchHeight - 10)
            if music.hasTrack {
                HStack(spacing: 10) {
                    cover.frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 9))
                        .onTapGesture { music.showPlayerWindow() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(music.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(music.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    }
                    Spacer()
                    Equalizer(playing: music.playing, height: 14)
                }
                HStack(spacing: 8) {
                    control("gobackward.10", "skipback", size: 13)
                    ProgressBar(music: music)
                    control("goforward.10", "skipfwd", size: 13)
                }
                HStack(spacing: 28) {
                    control("backward.fill", "prev", size: 14)
                    control(music.playing ? "pause.fill" : "play.fill", "toggle", size: 18)
                    control("forward.fill", "next", size: 14)
                }
            } else {
                Spacer()
                Text("Nada tocando").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                Spacer()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private func control(_ symbol: String, _ command: String, size: CGFloat = 17) -> some View {
        Button { music.send(command) } label: {
            Image(systemName: symbol).font(.system(size: size))
        }
        .buttonStyle(.plain)
    }
}

final class SeekState: ObservableObject {
    @Published var dragging: Double?
}

struct ProgressBar: View {
    @ObservedObject var music: MusicModel
    @StateObject private var seek = SeekState()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let total = max(music.duration, 1)
            let value = seek.dragging ?? music.position(at: context.date)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 4)
                    Capsule().fill(.white).frame(width: geometry.size.width * min(max(value / total, 0), 1), height: 4)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        seek.dragging = min(max(drag.location.x / geometry.size.width, 0), 1) * total
                    }
                    .onEnded { drag in
                        music.seek(to: min(max(drag.location.x / geometry.size.width, 0), 1) * total)
                        seek.dragging = nil
                    })
            }
            .frame(height: 14)
        }
    }
}
