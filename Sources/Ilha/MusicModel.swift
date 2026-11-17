import AppKit

@MainActor
final class MusicModel: ObservableObject {
    @Published var title = ""
    @Published var artist = ""
    @Published var duration = 0.0
    private var elapsedBase = 0.0
    private var sampledAt = Date()
    private var rate = 1.0
    @Published var cover: NSImage?
    @Published var playing = false

    var hasTrack: Bool { !title.isEmpty }
    /// Posição atual, estimada a partir da última leitura enquanto toca.
    func position(at date: Date = Date()) -> Double {
        let value = playing ? elapsedBase + date.timeIntervalSince(sampledAt) * rate : elapsedBase
        return min(max(value, 0), max(duration, 0))
    }

    /// Falso quando o macOS soltou a sessão de reprodução.
    private(set) var sessionLive = false

    private let library: String
    private let script: String
    private var buffer = Data()
    private var watcher: Process?

    init() {
        let resources = Bundle.main.resourcePath ?? "."
        library = resources + "/libIlhaNP.dylib"
        script = resources + "/np.pl"
        startWatching()
    }

    /// Arrastar a barra: pula a diferença em passos de 10 s e já mostra a nova posição.
    func seek(to seconds: Double) {
        let delta = seconds - position()
        elapsedBase = seconds
        sampledAt = Date()
        objectWillChange.send()
        Task.detached { await YTMusic.seek(by: delta) }
    }

    func showPlayerWindow() {
        Task.detached { await YTMusic.showWindow() }
    }

    func send(_ command: String) {
        if command == "skipfwd" || command == "skipback" {
            seek(to: position() + (command == "skipfwd" ? 10 : -10))
            return
        }
        if command == "toggle" { playing.toggle() }
        let (script, library) = (script, library)
        DispatchQueue.global().async {
            if YTMusic.control(command) { return }
            if command == "toggle" { Task { await YTMusic.resume() } }
            Self.run(script, library, command)
        }
    }

    private func startWatching() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script, library, "watch"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            Task { @MainActor in self?.consume(chunk) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.startWatching()
            }
        }
        do { try process.run(); watcher = process } catch {}
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            apply(line)
        }
    }

    private func apply(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        playing = json["playing"] as? Bool ?? false
        if let art = json["artwork"] as? String, let bytes = Data(base64Encoded: art), let image = NSImage(data: bytes) {
            cover = image
        }
        // Sem título = o macOS soltou a sessão: mantém a última faixa.
        guard let newTitle = json["title"] as? String, !newTitle.isEmpty else { sessionLive = false; return }
        sessionLive = true
        title = newTitle
        artist = json["artist"] as? String ?? ""
        duration = json["duration"] as? Double ?? 0
        elapsedBase = json["elapsedtime"] as? Double ?? 0
        sampledAt = (json["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
        rate = json["rate"] as? Double ?? 1
    }

    @discardableResult
    nonisolated private static func run(_ script: String, _ library: String, _ mode: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script, library, mode]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        return nil
    }
}
