import Foundation
import Security
import AppKit

enum MetaControllerDiscovery {
    // Read only the active Meta core's generated config, never scan ports or subscriptions.
    static func discover() async -> Int? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.metacubex.ClashX.meta").isEmpty else { return nil }
        return await Task.detached(priority: .utility) { discoverFromProcess() }.value
    }
    private static func output(_ arguments: [String]) -> String? {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            if task.isRunning { task.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0, data.count < 1_048_576 else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private static func discoverFromProcess() -> Int? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let core = home.appendingPathComponent("Library/Application Support/com.metacubex.ClashX.meta/.private_core/com.metacubex.ClashX.ProxyConfigHelper.meta").path
        guard let processes = output(["-ww", "-axo", "pid=,comm="]) else { return nil }
        let pids = processes.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard fields.count == 2, Int(fields[0]) != nil,
                  fields[1].trimmingCharacters(in: .whitespaces) == core else { return nil }
            return String(fields[0])
        }
        guard pids.count == 1, let arguments = output(["-ww", "-p", pids[0], "-o", "command="]),
              arguments.hasPrefix(core + " "), let range = arguments.range(of: " -f ") else { return nil }
        let path = String(arguments[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let root = home.appendingPathComponent("Library/Caches/com.MetaCubeX.ClashX.meta/cacheConfigs", isDirectory: true)
        guard permittedConfigPath(path, root: root) else { return nil }
        guard let file = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? file.close() }
        guard let data = try? file.read(upToCount: 8_388_609), data.count <= 8_388_608,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return controllerPort(in: text)
    }
    static func permittedConfigPath(_ path: String, root: URL) -> Bool {
        let url = URL(fileURLWithPath: path)
        return path.hasPrefix("/") && url.pathExtension == "yaml" &&
            url.resolvingSymlinksInPath().deletingLastPathComponent() == root.resolvingSymlinksInPath()
    }
    static func controllerPort(in text: String) -> Int? {
        if let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let endpoint = json["external-controller"] as? String { return loopbackPort(endpoint) }
        // Deliberately support only simple top-level scalar syntax; fail closed on complex YAML.
        var endpoints = [String]()
        for line in text.split(separator: "\n") where line.first?.isWhitespace == false {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard ["external-controller", "\"external-controller\"", "'external-controller'"].contains(key) else { continue }
            var value = line[line.index(after: colon)...].split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0].trimmingCharacters(in: .whitespaces)
            if let quote = value.first, ["\"", "'"].contains(quote), value.last == quote, value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            endpoints.append(value)
        }
        guard endpoints.count == 1 else { return nil }
        return loopbackPort(endpoints[0])
    }
    private static func loopbackPort(_ endpoint: String) -> Int? {
        let parts = endpoint.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, ["127.0.0.1", "localhost", "0.0.0.0"].contains(String(parts[0])),
              !parts[1].isEmpty, parts[1].allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(parts[1]) else { return nil }
        return AppSettings.validPort(number)
    }
}

enum AppSettings {
    private static let proxyPortKey = "proxyPort"
    private static let controlPortKey = "controlPort"
    private static let keychainService = "local.clash.metaswitch"
    private static let keychainAccount = "meta-api-secret"

    static var proxyPort: Int { validPort(UserDefaults.standard.integer(forKey: proxyPortKey)) ?? 7890 }
    static var socksPort: Int { validPort(UserDefaults.standard.integer(forKey: "socksPort")) ?? proxyPort }
    static var manualControlPort: Int { validPort(UserDefaults.standard.integer(forKey: controlPortKey)) ?? 9090 }
    static var automaticPorts: Bool {
        get { UserDefaults.standard.object(forKey: "automaticPorts") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "automaticPorts") }
    }
    // Assigned by the host's serialized refresh/action path; never persisted as a new manual setting.
    static var detectedControlPort: Int?
    static var detectedProxyPorts: ProxyPorts?
    static var controlPort: Int { automaticPorts ? detectedControlPort ?? manualControlPort : manualControlPort }
    static var proxyPorts: ProxyPorts? {
        automaticPorts ? detectedProxyPorts : ProxyPorts(http: proxyPort, socks: socksPort, mixed: 0)
    }
    static func validPort(_ value: Int) -> Int? { (1...65535).contains(value) ? value : nil }
    static func savePorts(proxy: Int, socks: Int, control: Int) {
        UserDefaults.standard.set(proxy, forKey: proxyPortKey)
        UserDefaults.standard.set(socks, forKey: "socksPort")
        UserDefaults.standard.set(control, forKey: controlPortKey)
        detectedControlPort = nil
        detectedProxyPorts = nil
    }
    static func apiSecret() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: keychainService,
                                    kSecAttrAccount as String: keychainAccount,
                                    kSecMatchLimit as String: kSecMatchLimitOne,
                                    kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }
    static func saveAPISecret(_ value: String) throws {
        let identity: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                       kSecAttrService as String: keychainService,
                                       kSecAttrAccount as String: keychainAccount]
        SecItemDelete(identity as CFDictionary)
        guard !value.isEmpty else { return }
        var item = identity
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CoreError.secureStorage }
    }
}

struct ProxyHistory: Decodable { let delay: Int; let time: String? }
struct ProxyItem: Decodable {
    let type: String
    let now: String?
    let all: [String]?
    let history: [ProxyHistory]?
}
struct DelayResponse: Decodable { let delay: Int }
enum DelayResult: Sendable {
    case measured(Int), failed
    var label: String {
        switch self {
        case .measured(let value): return "\(value) ms"
        case .failed: return "超时/失败"
        }
    }
}
struct ProxyResponse: Decodable { let proxies: [String: ProxyItem] }
struct ProxyPorts: Equatable {
    let http: Int
    let socks: Int
    let mixed: Int
    var httpUsed: Int { mixed > 0 ? mixed : http }
    var socksUsed: Int { mixed > 0 ? mixed : socks }
    var isUsable: Bool { [http, socks, mixed].allSatisfy { (0...65535).contains($0) } && (httpUsed > 0 || socksUsed > 0) }
    var summary: String { "HTTP/HTTPS \(httpUsed) · SOCKS \(socksUsed) · 混合 \(mixed)" }
}
struct CoreConfiguration: Decodable {
    let mode: String
    let port: Int?
    let socksPort: Int?
    let mixedPort: Int?
    enum CodingKeys: String, CodingKey { case mode, port, socksPort = "socks-port", mixedPort = "mixed-port" }
    var proxyPorts: ProxyPorts? {
        guard let port, let socksPort, let mixedPort else { return nil }
        let ports = ProxyPorts(http: port, socks: socksPort, mixed: mixedPort)
        return ports.isUsable ? ports : nil
    }
}
enum CoreError: LocalizedError {
    case unavailable, unauthorized, invalidSelection, verification, invalidSettings, secureStorage, unknownPorts
    var errorDescription: String? {
        switch self {
        case .unavailable: "无法连接本机 Meta 控制接口（127.0.0.1:\(AppSettings.controlPort)），请确认 ClashX Meta 已运行并检查端口。"
        case .unauthorized: "Meta 控制接口拒绝授权；请在兼容设置中填写 External Controller 密钥。"
        case .invalidSelection: "该节点或策略组已变化，请刷新后重新选择。"
        case .verification: "未确认切换成功，请刷新查看当前状态。"
        case .invalidSettings: "端口必须是 1 到 65535 之间的数字。"
        case .secureStorage: "无法将控制接口密钥保存到 macOS 钥匙串。"
        case .unknownPorts: "未读取到有效的 Meta 运行端口；未切换系统代理。请检查控制接口，或在兼容设置中关闭自动读取并填写 HTTP 与 SOCKS 端口。"
        }
    }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum CoreAPI {
    static func groupPath(_ name: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return "proxies/" + (name.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
    }
    private static func request(_ path: String, method: String = "GET", body: [String: String]? = nil,
                                queryItems: [URLQueryItem] = [], timeout: TimeInterval = 3) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 1
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var components = URLComponents(string: "http://127.0.0.1:\(AppSettings.controlPort)/" + path)!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        let secret = AppSettings.apiSecret()
        if !secret.isEmpty { request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CoreError.unavailable }
        if response.statusCode == 401 || response.statusCode == 403 { throw CoreError.unauthorized }
        guard (200..<300).contains(response.statusCode) else { throw CoreError.unavailable }
        return data
    }
    static func configuration() async throws -> CoreConfiguration {
        let configuration = try JSONDecoder().decode(CoreConfiguration.self, from: try await request("configs"))
        guard ["rule", "global", "direct"].contains(configuration.mode) else { throw CoreError.verification }
        return configuration
    }
    static func mode() async throws -> String { try await configuration().mode }
    static func proxies() async throws -> [String: ProxyItem] { try JSONDecoder().decode(ProxyResponse.self, from: try await request("proxies")).proxies }
    static func delay(_ node: String) async throws -> Int {
        guard let proxy = try await proxies()[node], !["Reject", "REJECT", "Pass", "PASS"].contains(proxy.type) else { throw CoreError.invalidSelection }
        let data = try await request(groupPath(node) + "/delay", queryItems: [
            URLQueryItem(name: "url", value: "https://www.gstatic.com/generate_204"),
            URLQueryItem(name: "timeout", value: "5000")
        ], timeout: 7)
        let value = try JSONDecoder().decode(DelayResponse.self, from: data).delay
        guard (1...65535).contains(value) else { throw CoreError.verification }
        return value
    }
    static func measureDelay(_ node: String?) async -> (String, DelayResult)? {
        guard let node, !Task.isCancelled else { return nil }
        do { return (node, .measured(try await delay(node))) }
        catch { return Task.isCancelled ? nil : (node, .failed) }
    }
    static func setMode(_ mode: String) async throws {
        guard ["rule", "global", "direct"].contains(mode) else { throw CoreError.invalidSelection }
        _ = try await request("configs", method: "PATCH", body: ["mode": mode])
        guard try await self.mode() == mode else { throw CoreError.verification }
    }
    static func setNode(_ node: String, group: String) async throws {
        let current = try await proxies()
        guard let selected = current[group], selected.type == "Selector", selected.all?.contains(node) == true else { throw CoreError.invalidSelection }
        _ = try await request(groupPath(group), method: "PUT", body: ["name": node])
        guard try await proxies()[group]?.now == node else { throw CoreError.verification }
    }
}
