import CEIA
import Foundation

// MARK: - Data exchanged with the Go engine (JSON)

struct Metrics: Codable, Sendable, Equatable {
    var columns: Int
    var rows: Int
    var dockMax: Int
    var folderColumns: Int
    var folderRows: Int
    var folderMaxPages: Int
    var maxPages: Int

    static let iPhone = Metrics(columns: 4, rows: 6, dockMax: 4, folderColumns: 3, folderRows: 3, folderMaxPages: 15, maxPages: 15)
}

struct DeviceInfo: Codable, Sendable {
    var name: String
    var ios: String
    var model: String
    var deviceClass: String
    var udid: String
    var usb: Bool
}

struct Item: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var type: String // app | widget | webclip | other
    var name: String
    var key: String?
    var size: String?
    var widget: String?

    var isWidget: Bool { type == "widget" }
}

struct Folder: Codable, Sendable, Equatable {
    var name: String
    var pages: [[String]]
}

struct LayoutView: Codable, Sendable {
    var items: [String: Item]
    var folders: [String: Folder]
    var dock: [String]
    var pages: [[String]]
    var sig: String
    var count: Int
    var metrics: Metrics
}

struct Payload: Codable, Sendable {
    var dock: [String]
    var pages: [[String]]
    var folders: [String: Folder]
    var sig: String
    var force: Bool
}

struct SaveResult: Codable, Sendable {
    var ok: Bool
    var backup: String
    var verified: Bool
    var conflict: String?
    var layout: LayoutView?
}

struct Backup: Codable, Sendable, Identifiable {
    var name: String
    var date: String
    var pages: Int
    var items: Int
    var id: String { name }
}

struct ConnectStatus: Codable, Sendable {
    var info: DeviceInfo
    var metrics: Metrics
}

/// An error from the engine: "code|arg|arg", translated by `L10n`.
struct EngineError: Error, Sendable {
    let raw: String
    var code: String { raw.components(separatedBy: "|").first ?? raw }
    var args: [String] { Array(raw.components(separatedBy: "|").dropFirst()) }
    var message: String { L10n.error(self) }
}

// MARK: - Calls into libeia (blocking, so always off the main thread)

enum Engine {
    private struct Envelope<T: Decodable>: Decodable {
        let ok: Bool
        let data: T?
        let error: String?
    }

    private struct Empty: Decodable {}

    private static func decode<T: Decodable>(_ ptr: UnsafeMutablePointer<CChar>?, as: T.Type) throws -> T? {
        guard let ptr else { throw EngineError(raw: "generic|no reply") }
        defer { EIAFree(ptr) }
        let data = Data(String(cString: ptr).utf8)
        let env = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard env.ok else { throw EngineError(raw: env.error ?? "generic") }
        return env.data
    }

    private static func required<T: Decodable>(_ ptr: UnsafeMutablePointer<CChar>?, as type: T.Type) throws -> T {
        guard let v = try decode(ptr, as: type) else { throw EngineError(raw: "generic|empty reply") }
        return v
    }

    private static func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try body() }.value
    }

    static func connect() async throws -> ConnectStatus {
        try await run { try required(EIAConnect(), as: ConnectStatus.self) }
    }

    static func loadLayout() async throws -> LayoutView {
        try await run { try required(EIALoadLayout(), as: LayoutView.self) }
    }

    static func save(_ payload: Payload) async throws -> SaveResult {
        let json = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        return try await run {
            try json.withCString { try required(EIASave(UnsafeMutablePointer(mutating: $0)), as: SaveResult.self) }
        }
    }

    static func backups() async throws -> [Backup] {
        try await run { try decode(EIAListBackups(), as: [Backup].self) ?? [] }
    }

    static func restore(_ name: String) async throws -> SaveResult {
        try await run {
            try name.withCString { try required(EIARestore(UnsafeMutablePointer(mutating: $0)), as: SaveResult.self) }
        }
    }

    static func revealBackups() {
        Task.detached { _ = try? decode(EIARevealBackups(), as: Empty.self) }
    }

    /// Path of the cached PNG for a bundle id, fetched from the iPhone if needed.
    static func iconPath(_ key: String) -> String? {
        let path = key.withCString { EIAIconPath(UnsafeMutablePointer(mutating: $0)) }
        guard let path else { return nil }
        defer { EIAFree(path) }
        let s = String(cString: path)
        return s.isEmpty ? nil : s
    }

    static func shutdown() { EIAShutdown() }
}
