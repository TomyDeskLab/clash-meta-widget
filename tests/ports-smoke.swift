import Foundation

// Read-only: discovers the running Meta controller and compares runtime ports to macOS.
@main struct PortsSmoke {
    static func main() async throws {
        guard let control = await MetaControllerDiscovery.discover() else {
            throw CoreError.unavailable
        }
        AppSettings.detectedControlPort = control
        let config = try await CoreAPI.configuration()
        guard let ports = config.proxyPorts else { throw CoreError.unknownPorts }
        AppSettings.detectedProxyPorts = ports
        guard let state = ProxyState.read() else { throw CoreError.unknownPorts }
        print("Discovered controller: \(control); \(ports.summary)")
        print("System enabled: \(state.enabled); foreign: \(state.foreignProxy)")
        print("Read-only check completed; no preferences or system proxies changed.")
    }
}
