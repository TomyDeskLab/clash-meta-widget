import Foundation
import Security

enum AppSettings {
    private static let proxyPortKey = "proxyPort"
    private static let controlPortKey = "controlPort"
    private static let keychainService = "local.clash.metaswitch"
    private static let keychainAccount = "meta-api-secret"

    static var proxyPort: Int { validPort(UserDefaults.standard.integer(forKey: proxyPortKey)) ?? 7890 }
    static var controlPort: Int { validPort(UserDefaults.standard.integer(forKey: controlPortKey)) ?? 9090 }
    static func validPort(_ value: Int) -> Int? { (1...65535).contains(value) ? value : nil }
    static func savePorts(proxy: Int, control: Int) {
        UserDefaults.standard.set(proxy, forKey: proxyPortKey)
        UserDefaults.standard.set(control, forKey: controlPortKey)
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
struct CoreConfiguration: Decodable { let mode: String }
enum CoreError: LocalizedError {
    case unavailable, unauthorized, invalidSelection, verification, invalidSettings, secureStorage
    var errorDescription: String? {
        switch self {
        case .unavailable: "无法连接本机 Meta 控制接口（127.0.0.1:\(AppSettings.controlPort)），请确认 ClashX Meta 已运行并检查端口。"
        case .unauthorized: "Meta 控制接口拒绝授权；请在兼容设置中填写 External Controller 密钥。"
        case .invalidSelection: "该节点或策略组已变化，请刷新后重新选择。"
        case .verification: "未确认切换成功，请刷新查看当前状态。"
        case .invalidSettings: "端口必须是 1 到 65535 之间的数字。"
        case .secureStorage: "无法将控制接口密钥保存到 macOS 钥匙串。"
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
    static func mode() async throws -> String { try JSONDecoder().decode(CoreConfiguration.self, from: try await request("configs")).mode }
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
