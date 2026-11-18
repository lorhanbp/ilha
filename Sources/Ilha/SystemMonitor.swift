import Foundation
import IOKit

@_silgen_name("IOHIDEventSystemClientCreate") private func hidClientCreate(_ allocator: CFAllocator?) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventSystemClientSetMatching") private func hidSetMatching(_ client: CFTypeRef, _ matching: CFDictionary)
@_silgen_name("IOHIDEventSystemClientCopyServices") private func hidCopyServices(_ client: CFTypeRef) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty") private func hidServiceProperty(_ service: CFTypeRef, _ key: CFString) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDServiceClientCopyEvent") private func hidServiceEvent(_ service: CFTypeRef, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventGetFloatValue") private func hidEventFloat(_ event: CFTypeRef, _ field: Int32) -> Double

/// CPU, memória, GPU e temperaturas. Os sensores de temperatura vêm da API privada do IOHID.
@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var cpu = 0
    @Published private(set) var memoryPercent = 0
    @Published private(set) var memoryUsedGB = 0.0
    @Published private(set) var memoryTotalGB = 0.0
    @Published private(set) var storagePercent = 0
    @Published private(set) var storageUsedGB = 0.0
    @Published private(set) var storageTotalGB = 0.0
    @Published private(set) var gpu: Int?
    @Published private(set) var cpuTemperature: Int?
    @Published private(set) var batteryTemperature: Int?

    private var lastTicks: (used: UInt64, total: UInt64)?
    private let hidClient: CFTypeRef?

    init() {
        hidClient = hidClientCreate(kCFAllocatorDefault)?.takeRetainedValue()
        if let hidClient { hidSetMatching(hidClient, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary) }
        refresh()
    }

    /// Só lê os sensores enquanto a ilha está aberta: é o único momento em que alguém vê os números.
    var active = false {
        didSet {
            guard active != oldValue else { return }
            timer?.invalidate()
            timer = nil
            guard active else { return }
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }
    private var timer: Timer?

    private func refresh() {
        readCPU()
        readMemory()
        gpu = readGPU()
        readStorage()
        readTemperatures()
    }

    private func readCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1), idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let used = user + system + nice
        let total = used + idle
        if let last = lastTicks, total > last.total {
            cpu = Int((Double(used - last.used) / Double(total - last.total) * 100).rounded())
        }
        lastTicks = (used, total)
    }

    private func readMemory() {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return }
        let pages = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let used = Double(pages) * Double(vm_kernel_page_size)
        memoryTotalGB = total / 1_073_741_824
        memoryUsedGB = used / 1_073_741_824
        memoryPercent = Int(min(100, used / total * 100))
    }

    /// Disco de inicialização (o NVMe interno), em GB decimais como o Finder mostra.
    private func readStorage() {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacityForImportantUsage, total > 0 else { return }
        let used = Double(total) - Double(free)
        storageTotalGB = Double(total) / 1_000_000_000
        storageUsedGB = used / 1_000_000_000
        storagePercent = Int(min(100, max(0, used / Double(total) * 100)))
    }

    private func readGPU() -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Int?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let statistics = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any]
            if let value = (statistics?["Device Utilization %"] as? NSNumber)?.intValue { best = max(best ?? 0, value) }
        }
        return best
    }

    private func readTemperatures() {
        guard let hidClient, let services = hidCopyServices(hidClient)?.takeRetainedValue() as? [AnyObject] else { return }
        var die: [Double] = [], battery: [Double] = []
        for service in services {
            let name = (hidServiceProperty(service, "Product" as CFString)?.takeRetainedValue() as? String) ?? ""
            guard name.contains("tdie") || name.contains("gas gauge battery"),
                  let event = hidServiceEvent(service, 15, 0, 0)?.takeRetainedValue() else { continue }
            let value = hidEventFloat(event, 15 << 16)
            guard value > 0, value < 150 else { continue }
            if name.contains("tdie") { die.append(value) } else { battery.append(value) }
        }
        cpuTemperature = die.max().map { Int($0.rounded()) }
        batteryTemperature = battery.isEmpty ? nil : Int((battery.reduce(0, +) / Double(battery.count)).rounded())
    }
}
