import Foundation

struct Accessory: Identifiable, Equatable {
    var id: String
    var name: String
    var symbol: String
    var battery: String?

    /// Nome mostrado na ilha: o Magic Mouse ganha o nome do modelo em vez do nome que o dono deu a ele.
    var displayName: String {
        if symbol == "magicmouse.fill" { return "Magic Mouse" }
        if symbol == "keyboard.fill" && name.lowercased().contains("keyboard") == false && name.lowercased().contains("teclado") == false { return "Teclado" }
        return name
    }

    var level: Int? { battery.flatMap { Int($0.filter(\.isNumber).prefix(3)) } }
}

/// Acessórios Bluetooth conectados e a bateria deles; avisa quando um conecta ou chega a 20%.
@MainActor
final class AccessoryMonitor: ObservableObject {
    @Published private(set) var devices: [Accessory] = []
    var onAnnounce: (Accessory, Bool) -> Void = { _, _ in }
    private var known: Set<String>?
    private var lowNotified: Set<String> = []
    private var fast: [Accessory] = []
    private var slow: [Accessory] = []
    private var previous: [String: Accessory] = [:]
    private var fastLoaded = false
    private var slowLoaded = false

    init() {
        pollSlow()
        pollFast()
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollSlow() }
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollFast() }
        }
    }

    private func pollSlow() {
        DispatchQueue.global().async {
            let list = Self.readBluetooth()
            DispatchQueue.main.async { [weak self] in
                guard let list else { return }
                self?.slow = list
                self?.slowLoaded = true
                self?.merge()
            }
        }
    }

    private func pollFast() {
        DispatchQueue.global().async {
            let list = Self.readFast()
            DispatchQueue.main.async { [weak self] in
                self?.fast = list
                self?.fastLoaded = true
                self?.merge()
            }
        }
    }

    private func merge() {
        var seen = Set<String>()
        var list: [Accessory] = []
        for device in fast + slow where seen.insert(device.id).inserted {
            var device = device
            if device.battery == nil, let other = slow.first(where: { $0.id == device.id })?.battery { device.battery = other }
            list.append(device)
        }
        apply(list)
    }

    private func apply(_ list: [Accessory]) {
        guard list != devices else { return }
        devices = list
        let ids = Set(list.map(\.id))
        defer {
            known = ids
            previous = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        guard let known, fastLoaded, slowLoaded else { return }
        for id in known.subtracting(ids) {
            if let gone = previous[id] { onAnnounce(gone, false) }
        }
        for device in list {
            if !known.contains(device.id) {
                onAnnounce(device, true)
            } else if let level = device.level, level <= 20, !lowNotified.contains(device.id) {
                lowNotified.insert(device.id)
                onAnnounce(device, true)
            }
            if let level = device.level, level > 25 { lowNotified.remove(device.id) }
        }
    }

    nonisolated private static func run(_ path: String, _ arguments: [String]) -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return Data() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    /// ioreg é rápido: aparelhos HID com bateria (mouse, teclado) e iPhone/iPad por cabo.
    nonisolated private static func readFast() -> [Accessory] {
        var result: [Accessory] = []
        let hid = String(decoding: run("/usr/sbin/ioreg", ["-r", "-k", "BatteryPercent", "-w0"]), as: UTF8.self)
        for block in hid.components(separatedBy: "+-o ") {
            guard let product = capture(#""Product" = "([^"]+)""#, in: block),
                  let percent = capture(#""BatteryPercent" = (\d+)"#, in: block) else { continue }
            let address = capture(#""DeviceAddress" = "([^"]+)""#, in: block) ?? product
            let vendor = Int(capture(#""VendorID" = (\d+)"#, in: block) ?? "") ?? 0
            let productID = Int(capture(#""ProductID" = (\d+)"#, in: block) ?? "") ?? 0
            result.append(Accessory(id: address.replacingOccurrences(of: "-", with: ":").uppercased(), name: product,
                                    symbol: hidSymbol(vendor: vendor, product: productID, name: product.lowercased()),
                                    battery: "\(percent)%"))
        }
        let usb = String(decoding: run("/usr/sbin/ioreg", ["-p", "IOUSB", "-l", "-w0"]), as: UTF8.self)
        for block in usb.components(separatedBy: "+-o ") {
            guard let name = capture(#""USB Product Name" = "([^"]+)""#, in: block) else { continue }
            let lower = name.lowercased()
            guard lower.contains("iphone") || lower.contains("ipad") else { continue }
            let serial = capture(#""USB Serial Number" = "([^"]+)""#, in: block) ?? name
            result.append(Accessory(id: "usb-" + serial, name: name, symbol: lower.contains("ipad") ? "ipad" : "iphone", battery: nil))
        }
        return result
    }

    /// Sem lista de conectados, o JSON é válido mas vazio: nada conectado por Bluetooth.
    nonisolated private static func section0() -> [Accessory] { [] }

    nonisolated private static func hidSymbol(vendor: Int, product: Int, name: String) -> String {
        if vendor == 76 {
            if [0x0269, 0x030D, 0x0323].contains(product) { return "magicmouse.fill" }
            if [0x0265, 0x0314, 0x0324].contains(product) { return "rectangle.and.hand.point.up.left.fill" }
            return "keyboard.fill"
        }
        if name.contains("mouse") { return "computermouse.fill" }
        if name.contains("keyboard") { return "keyboard.fill" }
        return "dot.radiowaves.left.and.right"
    }

    nonisolated private static func readBluetooth() -> [Accessory]? {
        guard let root = try? JSONSerialization.jsonObject(with: run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"])) as? [String: Any],
              let section = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = section["device_connected"] as? [[String: Any]] else { return section0() }

        var result: [Accessory] = []
        for entry in connected {
            for (name, value) in entry {
                guard let info = value as? [String: Any] else { continue }
                let kind = (info["device_minorType"] as? String ?? "").lowercased()
                var battery = ["device_batteryLevelMain", "device_batteryLevelLeft", "device_batteryLevelRight"]
                    .compactMap { info[$0] as? String }
                if battery.count > 1 { battery = [battery.min() ?? battery[0]] }
                let address = ((info["device_address"] as? String) ?? name).replacingOccurrences(of: "-", with: ":").uppercased()
                result.append(Accessory(id: address, name: name, symbol: symbol(name: name.lowercased(), kind: kind),
                                        battery: battery.first))
            }
        }
        return result
    }

    nonisolated private static func symbol(name: String, kind: String) -> String {
        if name.contains("iphone") { return "iphone" }
        if name.contains("ipad") { return "ipad" }
        if kind.contains("mouse") { return "magicmouse.fill" }
        if kind.contains("keyboard") { return "keyboard.fill" }
        if kind.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpods.pro" }
        if name.contains("airpods") { return "airpods" }
        if kind.contains("head") || kind.contains("earb") || kind.contains("speaker") { return "headphones" }
        return "dot.radiowaves.left.and.right"
    }

    nonisolated private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
