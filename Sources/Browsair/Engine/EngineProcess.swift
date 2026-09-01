import Foundation

enum EngineError: LocalizedError {
    case binaryMissing(String)
    case startFailed(String)
    case notRunning
    case healthCheckTimedOut

    var errorDescription: String? {
        switch self {
        case .binaryMissing(let path):
            return "Obscura engine not found at \(path). Run scripts/fetch-engine.sh"
        case .startFailed(let message):
            return "Failed to start Obscura: \(message)"
        case .notRunning:
            return "Obscura engine is not running"
        case .healthCheckTimedOut:
            return "Obscura did not become ready in time"
        }
    }
}

/// Owns the child `obscura serve` process.
final class EngineProcess: @unchecked Sendable {
    private(set) var port: Int = 0
    private var process: Process?

    var isRunning: Bool {
        process?.isRunning == true
    }

    static func resolveBinaryURL() throws -> URL {
        // 1) SwiftPM resource bundle (preferred when packaged)
        if let resourceURL = Bundle.module.url(forResource: "obscura", withExtension: nil, subdirectory: "Engine") {
            return resourceURL
        }
        if let resourceURL = Bundle.module.url(forResource: "obscura", withExtension: nil) {
            return resourceURL
        }

        // 2) Vendor/ next to the package (swift run from repo root)
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            cwd.appendingPathComponent("Vendor/obscura/obscura"),
            cwd.appendingPathComponent("Sources/Browsair/Resources/Engine/obscura"),
            // Walk up from the executable location
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("Vendor/obscura/obscura"),
        ]
        for url in candidates where FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }

        throw EngineError.binaryMissing(candidates.map(\.path).joined(separator: ", "))
    }

    static func storageDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("Browsair", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start() async throws -> Int {
        if isRunning { return port }

        let binary = try Self.resolveBinaryURL()
        let storage = try Self.storageDirectory()
        let freePort = try Self.ephemeralPort()

        let proc = Process()
        proc.executableURL = binary
        proc.arguments = [
            "serve",
            "--host", "127.0.0.1",
            "--port", "\(freePort)",
            "--storage-dir", storage.path,
            "--quiet",
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            throw EngineError.startFailed(error.localizedDescription)
        }

        process = proc
        port = freePort

        try await waitUntilHealthy(port: freePort, timeout: 15)
        return freePort
    }

    func stop() {
        let proc = process
        process = nil

        guard let proc else { return }
        if proc.isRunning {
            proc.terminate()
            let deadline = Date().addingTimeInterval(2)
            while proc.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if proc.isRunning {
                proc.interrupt()
                kill(proc.processIdentifier, SIGKILL)
            }
        }
    }

    deinit { stop() }

    private func waitUntilHealthy(port: Int, timeout: TimeInterval) async throws {
        let url = URL(string: "http://127.0.0.1:\(port)/json/version")!
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !(process?.isRunning ?? false) {
                throw EngineError.startFailed("process exited early")
            }
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    return
                }
            } catch {
                // keep polling
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw EngineError.healthCheckTimedOut
    }

    private static func ephemeralPort() throws -> Int {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw EngineError.startFailed("socket()") }
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw EngineError.startFailed("bind()") }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getsock = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFD, $0, &len)
            }
        }
        guard getsock == 0 else { throw EngineError.startFailed("getsockname()") }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}
