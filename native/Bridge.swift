import Foundation
import Security
import Darwin

struct Snapshot: Codable {
    var date: Date
    var enabled: Bool
    var foreignProxy: Bool
    var running: Bool
    var ticket: String
    var expires: Date
    var targetEnabled: Bool
    var mode: String? = nil
    var node: String? = nil
    var group: String? = nil
    var coreOnline: Bool? = nil
    var modeTickets: [String: String]? = nil
    var nodeOptions: [String]? = nil
    var nodeTicket: String? = nil
    var selection: String? = nil
    var canAct: Bool { running && !foreignProxy && expires > Date() }
    var actionURL: URL? {
        guard canAct else { return nil }
        return URL(string: "clash-meta-switch://apply/" + ticket)
    }
    func modeURL(_ mode: String) -> URL? {
        guard canAct, coreOnline == true, ["rule", "global", "direct"].contains(mode), let token = modeTickets?[mode] else { return nil }
        return URL(string: "clash-meta-switch://" + mode + "/" + token)
    }
    func nodeURL(_ name: String) -> URL? {
        guard canAct, coreOnline == true, nodeOptions?.contains(name) == true, let token = nodeTicket else { return nil }
        let encoded = Data(name.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return URL(string: "clash-meta-switch://node/\(token)/\(encoded)")
    }
}

enum Bridge {
    static var directory: URL {
        // Sandbox homeDirectory points inside the extension container. Resolve the user's real home.
        let home = String(cString: getpwuid(getuid())!.pointee.pw_dir)
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/ClashMetaSwitch", isDirectory: true)
    }
    static var file: URL { directory.appendingPathComponent("snapshot.json") }
    static func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: file), data.count < 65536 else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
    static func randomTicket() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw BridgeError.storage }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    static func validates(_ url: URL, snapshot: Snapshot, now: Date = Date()) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "clash-meta-switch", let action = components.host,
              ["apply", "rule", "global", "direct", "node"].contains(action),
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil,
              snapshot.expires > now, snapshot.running, !snapshot.foreignProxy else { return false }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard action == "apply" || snapshot.coreOnline == true else { return false }
        let token = parts.first.map(String.init) ?? ""
        let expectedValue = action == "apply" ? snapshot.ticket : (action == "node" ? snapshot.nodeTicket ?? "" : snapshot.modeTickets?[action] ?? "")
        let candidate = Array(token.utf8), expected = Array(expectedValue.utf8)
        guard components.path == "/" + parts.joined(separator: "/"), candidate.count == 64, expected.count == 64,
              (action == "node" ? parts.count == 2 && nodeName(from: url, snapshot: snapshot) != nil : parts.count == 1) else { return false }
        return zip(candidate, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    static func nodeName(from url: URL, snapshot: Snapshot) -> String? {
        guard url.scheme == "clash-meta-switch", url.host == "node" else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), let name = String(data: data, encoding: .utf8), snapshot.nodeOptions?.contains(name) == true else { return nil }
        return name
    }
    #if !WIDGET_EXTENSION
    static func write(_ snapshot: Snapshot) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // Use a private temporary file and atomic rename, with permissions applied before publication.
        let temp = directory.appendingPathComponent(UUID().uuidString)
        let data = try JSONEncoder().encode(snapshot)
        guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw BridgeError.storage }
        defer { try? fm.removeItem(at: temp) }
        guard rename(temp.path, file.path) == 0 else { throw BridgeError.storage }
    }
    #endif
}

enum BridgeError: LocalizedError {
    case storage, expired
    var errorDescription: String? {
        switch self {
        case .storage: "无法保存组件状态；未更改代理。"
        case .expired: "组件画面已过期，已请求刷新。请稍后点按更新后的开关。"
        }
    }
}
