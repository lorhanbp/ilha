import Foundation
import IOKit
import IOKit.ps

/// Bateria e energia lidas do AppleSmartBattery.
@MainActor
final class EnergyModel: ObservableObject {
    @Published private(set) var percent = 0
    @Published private(set) var plugged = false
    @Published private(set) var charging = false
    @Published private(set) var systemWatts: Double?
    @Published private(set) var adapterRated: Int?
    @Published private(set) var adapterInWatts: Double?
    @Published private(set) var adapterVolts: Double?
    @Published private(set) var health: Int?
    @Published private(set) var cycles: Int?
    @Published private(set) var minutes: Int?

    init() {
        refresh()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let model = Unmanaged<EnergyModel>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { model.refresh() } }
        }, Unmanaged.passUnretained(self).toOpaque()).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    /// Porcentagem e tomada chegam por aviso do macOS; watts e tempo restante só são lidos com a ilha aberta.
    var active = false {
        didSet {
            guard active != oldValue else { return }
            timer?.invalidate()
            timer = nil
            guard active else { return }
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }
    private var timer: Timer?

    private func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

    private func refresh() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return }

        percent = Int(number(dictionary["CurrentCapacity"]) ?? 0)
        plugged = (dictionary["ExternalConnected"] as? Bool) ?? false
        charging = (dictionary["IsCharging"] as? Bool) ?? false
        cycles = number(dictionary["CycleCount"]).map(Int.init)

        let battery = dictionary["BatteryData"] as? [String: Any]
        if let nominal = number(battery?["NominalChargeCapacity"]), let design = number(battery?["DesignCapacity"]), design > 0 {
            health = min(100, Int(nominal / design * 100))
        }

        let telemetry = dictionary["PowerTelemetryData"] as? [String: Any]
        systemWatts = number(telemetry?["SystemLoad"]).map { $0 / 1000 }
        adapterInWatts = number(telemetry?["SystemPowerIn"]).map { $0 / 1000 }
        adapterVolts = number(telemetry?["SystemVoltageIn"]).map { $0 / 1000 }
        let adapter = dictionary["AdapterDetails"] as? [String: Any]
        adapterRated = number(adapter?["Watts"]).map(Int.init)

        let key = charging ? "AvgTimeToFull" : "AvgTimeToEmpty"
        if let value = number(dictionary[key]), value < 65535 { minutes = Int(value) } else { minutes = nil }
    }
}
