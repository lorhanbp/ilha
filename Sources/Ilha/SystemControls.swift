import CoreAudio
import CoreGraphics
import Foundation

/// Volume (CoreAudio) e brilho (DisplayServices, API privada) do sistema.
enum SystemControls {
    private static func outputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        return device
    }

    private static func property<T: BinaryFloatingPoint>(_ selector: AudioObjectPropertySelector, _ type: T.Type) -> (AudioDeviceID, AudioObjectPropertyAddress)? {
        guard let device = outputDevice() else { return nil }
        return (device, AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                                   mElement: kAudioObjectPropertyElementMain))
    }

    private static let virtualMainVolume: AudioObjectPropertySelector = 0x766D7663 // 'vmvc'

    static func volume() -> Float? {
        guard let (device, address) = property(virtualMainVolume, Float.self) else { return nil }
        var address2 = address, value = Float32(0), size = UInt32(4)
        return AudioObjectGetPropertyData(device, &address2, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func setVolume(_ value: Float) -> Bool {
        guard let (device, address) = property(virtualMainVolume, Float.self) else { return false }
        var address2 = address, v = min(max(value, 0), 1)
        return AudioObjectSetPropertyData(device, &address2, 0, nil, 4, &v) == noErr
    }

    static func muted() -> Bool {
        guard let device = outputDevice() else { return false }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value = UInt32(0), size = UInt32(4)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    static func setMuted(_ muted: Bool) {
        guard let device = outputDevice() else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &address, 0, nil, 4, &value)
    }

    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private static let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    private static var builtinDisplay: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func brightness() -> Float? {
        guard let display = builtinDisplay, let handle = displayServices,
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        var value: Float = 0
        return unsafeBitCast(symbol, to: GetBrightness.self)(display, &value) == 0 ? value : nil
    }

    static func setBrightness(_ value: Float) -> Bool {
        guard let display = builtinDisplay, let handle = displayServices,
              let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return false }
        return unsafeBitCast(symbol, to: SetBrightness.self)(display, min(max(value, 0), 1)) == 0
    }
}
