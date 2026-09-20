import Foundation
import SystemConfiguration

struct ProxyState {
    let enabled: Bool
    let foreignProxy: Bool
    static func read() -> ProxyState? {
        guard let settings = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return nil }
        return parse(settings, expectedPort: AppSettings.proxyPort)
    }
    static func parse(_ settings: [String: Any], expectedPort: Int = 7890) -> ProxyState {
        var local = false
        var foreign = (settings["ProxyAutoConfigEnable"] as? Int ?? 0) == 1 || (settings["ProxyAutoDiscoveryEnable"] as? Int ?? 0) == 1
        for kind in ["HTTP", "HTTPS", "SOCKS"] {
            guard (settings[kind + "Enable"] as? Int ?? 0) == 1 else { continue }
            let host = settings[kind + "Proxy"] as? String ?? ""
            let port = settings[kind + "Port"] as? Int ?? 0
            if ["127.0.0.1", "localhost", "::1"].contains(host) && port == expectedPort { local = true }
            else { foreign = true }
        }
        return ProxyState(enabled: local, foreignProxy: foreign)
    }
}
