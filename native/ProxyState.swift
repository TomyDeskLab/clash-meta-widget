import Foundation
import SystemConfiguration

struct ProxyState {
    let enabled: Bool
    let foreignProxy: Bool
    // Allowlisted diagnostics: never include proxy hostnames, PAC URLs or credentials.
    let diagnosticSummary: String
    static func read() -> ProxyState? {
        guard let settings = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return nil }
        guard let ports = AppSettings.proxyPorts else { return nil }
        return parse(settings, expectedPorts: ports)
    }
    static func parse(_ settings: [String: Any], expectedPort: Int = 7890) -> ProxyState {
        parse(settings, expectedPorts: ProxyPorts(http: expectedPort, socks: expectedPort, mixed: 0))
    }
    static func parse(_ settings: [String: Any], expectedPorts: ProxyPorts) -> ProxyState {
        var local = false
        var foreign = (settings["ProxyAutoConfigEnable"] as? Int ?? 0) == 1 || (settings["ProxyAutoDiscoveryEnable"] as? Int ?? 0) == 1
        var details = [String]()
        for kind in ["HTTP", "HTTPS", "SOCKS"] {
            guard (settings[kind + "Enable"] as? Int ?? 0) == 1 else {
                details.append("\(kind)=关")
                continue
            }
            let host = settings[kind + "Proxy"] as? String ?? ""
            let port = settings[kind + "Port"] as? Int ?? 0
            let loopback = ["127.0.0.1", "localhost", "::1"].contains(host)
            details.append("\(kind)=开/\(loopback ? "本机" : "非本机或未知"):\(port)")
            let expectedPort = kind == "SOCKS" ? expectedPorts.socksUsed : expectedPorts.httpUsed
            if loopback && port > 0 && port == expectedPort { local = true }
            else { foreign = true }
        }
        details.append("PAC=\((settings["ProxyAutoConfigEnable"] as? Int ?? 0) == 1 ? "开" : "关")")
        details.append("WPAD=\((settings["ProxyAutoDiscoveryEnable"] as? Int ?? 0) == 1 ? "开" : "关")")
        return ProxyState(enabled: local, foreignProxy: foreign, diagnosticSummary: details.joined(separator: "; "))
    }
}
