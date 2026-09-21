import Foundation
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label); checks += 1
}
let now = Date()
let ticket = try Bridge.randomTicket()
let snapshot = Snapshot(date: now, enabled: false, foreignProxy: false, running: true, ticket: ticket, expires: now.addingTimeInterval(30), targetEnabled: true)
let url = URL(string: "clash-meta-switch://apply/" + ticket)!
check(Bridge.validates(url, snapshot: snapshot, now: now), "valid ticket")
for attack in ["clash-meta-switch://apply/forged", "https://apply/" + ticket, "clash-meta-switch://other/" + ticket, url.absoluteString + "?value=false", url.absoluteString + "#fragment", "clash-meta-switch://user@apply/" + ticket, "clash-meta-switch://apply:80/" + ticket] {
    check(!Bridge.validates(URL(string: attack)!, snapshot: snapshot, now: now), "reject altered URL")
}
check(Bridge.validates(url, snapshot: snapshot, now: now.addingTimeInterval(864000)), "cached card survives timeline delay")
var rotated = snapshot; rotated.ticket = try Bridge.randomTicket()
check(!Bridge.validates(url, snapshot: rotated), "explicit credential revocation")
var stopped = snapshot; stopped.running = false
check(!Bridge.validates(url, snapshot: stopped), "reject stopped core")
var foreign = snapshot; foreign.foreignProxy = true
check(!Bridge.validates(url, snapshot: foreign), "reject conflicting proxy")
check(!ProxyState.parse([:]).enabled, "empty config")
check(ProxyState.parse(["HTTPEnable":1,"HTTPProxy":"127.0.0.1","HTTPPort":7890]).enabled, "Meta port")
check(ProxyState.parse(["HTTPEnable":1,"HTTPProxy":"127.0.0.1","HTTPPort":17890], expectedPort: 17890).enabled, "custom Meta port")
check(ProxyState.parse(["HTTPEnable":1,"HTTPProxy":"127.0.0.1","HTTPPort":7890], expectedPort: 17890).foreignProxy, "wrong configured port")
check(ProxyState.parse(["HTTPEnable":1,"HTTPProxy":"127.0.0.1","HTTPPort":8888]).foreignProxy, "other port")
check(ProxyState.parse(["ProxyAutoConfigEnable":1]).foreignProxy, "PAC")
check(ProxyState.parse(["ProxyAutoDiscoveryEnable":1]).foreignProxy, "WPAD")
check(ProxyState.parse(["HTTPEnable":1,"HTTPProxy":"example.org","HTTPPort":7890]).foreignProxy, "remote proxy")
var modes = snapshot
modes.coreOnline = true
modes.modeTickets = ["rule": try Bridge.randomTicket(), "global": try Bridge.randomTicket(), "direct": try Bridge.randomTicket()]
for mode in ["rule", "global", "direct"] {
    let action = modes.modeURL(mode)!
    check(Bridge.validates(action, snapshot: modes), "accept explicit mode")
    check(!Bridge.validates(URL(string: "clash-meta-switch://\(mode)/" + ticket)!, snapshot: modes), "power token cannot change mode")
    var offline = modes; offline.coreOnline = false
    check(!Bridge.validates(action, snapshot: offline), "offline mode cannot act")
    var consumed = modes; consumed.modeTickets?[mode] = try Bridge.randomTicket()
    check(!Bridge.validates(action, snapshot: consumed), "consumed mode token cannot replay")
}
check(modes.modeURL("unknown") == nil, "unknown mode rejected")
check(!Bridge.validates(URL(string: "clash-meta-switch://global/" + modes.modeTickets!["rule"]!)!, snapshot: modes), "mode tokens are action specific")
check(CoreAPI.groupPath("x/../configs?mode=direct#fragment") == "proxies/x%2F%2E%2E%2Fconfigs%3Fmode%3Ddirect%23fragment", "group cannot inject URL path or query")
check(CoreAPI.groupPath("曲面空间").hasPrefix("proxies/%"), "unicode group encoded")
check(!Bridge.validates(URL(string: "clash-meta-switch://controls")!, snapshot: modes), "navigation URL cannot mutate")
var nodes = modes
nodes.group = "曲面空间"
nodes.nodeOptions = ["🇸🇬新加坡A01", "🇨🇳台湾A02"]
nodes.nodeTicket = try Bridge.randomTicket()
let nodeURL = nodes.nodeURL("🇸🇬新加坡A01")!
check(Bridge.validates(nodeURL, snapshot: nodes), "valid node capability")
check(Bridge.nodeName(from: nodeURL, snapshot: nodes) == "🇸🇬新加坡A01", "node name round trip")
check(nodes.nodeURL("not-listed") == nil, "unlisted node has no capability")
var changedNodes = nodes; changedNodes.nodeOptions = ["🇨🇳台湾A02"]
check(!Bridge.validates(nodeURL, snapshot: changedNodes), "stale node rejected")
var consumedNode = nodes; consumedNode.nodeTicket = try Bridge.randomTicket()
check(!Bridge.validates(nodeURL, snapshot: consumedNode), "consumed node token cannot replay")
check(!Bridge.validates(URL(string: url.absoluteString + "/")!, snapshot: snapshot), "reject trailing slash")
check(!Bridge.validates(URL(string: url.absoluteString.replacingOccurrences(of: "apply/", with: "apply//"))!, snapshot: snapshot), "reject doubled path slash")
check(AppSettings.validPort(1) == 1 && AppSettings.validPort(65535) == 65535, "valid port bounds")
check(AppSettings.validPort(0) == nil && AppSettings.validPort(65536) == nil, "invalid port bounds")
var refreshed = nodes
refreshed.enabled.toggle()
refreshed.targetEnabled.toggle()
refreshed.mode = "global"
refreshed.date = now.addingTimeInterval(864000)
check(Bridge.validates(url, snapshot: refreshed), "same power link works after state refresh")
check(Bridge.validates(nodes.modeURL("rule")!, snapshot: refreshed), "same mode link works after state refresh")
for step in [-1, 1] {
    check(Bridge.validates(nodes.stepURL(step)!, snapshot: refreshed), "relative node link survives selection refresh")
}
check(nodes.stepURL(0) == nil, "invalid node step rejected")
check(!Bridge.validates(URL(string: "clash-meta-switch://next/" + ticket)!, snapshot: nodes), "power token cannot step nodes")
let separatePorts = ProxyState.parse(["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 7890,
                                     "SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 7891])
check(separatePorts.enabled && separatePorts.foreignProxy, "separate ports remain fail-closed until explicitly supported")
check(separatePorts.diagnosticSummary.contains("SOCKS=开/本机:7891"), "diagnostic exposes port mismatch")
let privateProxy = ProxyState.parse(["HTTPEnable": 1, "HTTPProxy": "private.corp.example", "HTTPPort": 8080,
                                    "ProxyAutoConfigEnable": 1, "ProxyAutoConfigURLString": "https://private.example/?secret=do-not-copy"])
check(!privateProxy.diagnosticSummary.contains("private") && !privateProxy.diagnosticSummary.contains("secret"), "diagnostic excludes remote host and PAC credentials")
check(privateProxy.diagnosticSummary.contains("PAC=开"), "diagnostic retains PAC enable flag")
check(ProxyState.parse([:]).diagnosticSummary.contains("HTTP=关"), "disabled proxy diagnostic is explicit")
let splitConfig = try JSONDecoder().decode(CoreConfiguration.self, from: Data(#"{"mode":"rule","port":17890,"socks-port":17891,"mixed-port":0}"#.utf8))
let splitPorts = splitConfig.proxyPorts!
let splitSystem: [String: Any] = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 17890,
                                 "HTTPSEnable": 1, "HTTPSProxy": "localhost", "HTTPSPort": 17890,
                                 "SOCKSEnable": 1, "SOCKSProxy": "::1", "SOCKSPort": 17891]
check(ProxyState.parse(splitSystem).foreignProxy, "build 10 fixed-port behavior rejects non-default split setup")
let detectedSplit = ProxyState.parse(splitSystem, expectedPorts: splitPorts)
check(detectedSplit.enabled && !detectedSplit.foreignProxy, "runtime split ports recognize Meta instead of blocking shutdown")
check(!ProxyState.parse([:], expectedPorts: splitPorts).enabled, "split-port shutdown recognized")
let mixedPorts = ProxyPorts(http: 17890, socks: 17891, mixed: 27890)
check(mixedPorts.httpUsed == 27890 && mixedPorts.socksUsed == 27890, "mixed port takes precedence for both protocols")
check(ProxyState.parse(splitSystem, expectedPorts: mixedPorts).foreignProxy, "old ports are not accepted after runtime change")
check(!ProxyState.parse(["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 27890], expectedPorts: mixedPorts).foreignProxy, "new runtime mixed port recognized")
check(ProxyState.parse(["HTTPEnable": 1, "HTTPProxy": "remote.example", "HTTPPort": 27890], expectedPorts: mixedPorts).foreignProxy, "automatic mode still rejects remote proxies")
check(ProxyState.parse(["ProxyAutoConfigEnable": 1], expectedPorts: mixedPorts).foreignProxy, "automatic mode still rejects PAC")
check(!ProxyPorts(http: 0, socks: 0, mixed: 0).isUsable, "all listeners disabled cannot authorize switching")
check(!ProxyPorts(http: 1, socks: -1, mixed: 7890).isUsable, "invalid config cannot be hidden by mixed port")
let incomplete = try JSONDecoder().decode(CoreConfiguration.self, from: Data(#"{"mode":"rule","port":7890}"#.utf8))
check(incomplete.proxyPorts == nil, "missing runtime fields cannot silently use guessed ports")
for text in ["external-controller: 127.0.0.1:19090", "external-controller: 'localhost:19090' # comment", #"{"external-controller":"0.0.0.0:19090"}"#] {
    check(MetaControllerDiscovery.controllerPort(in: text) == 19090, "runtime controller supports safe scalar and JSON")
}
for text in ["external-controller: attacker.example:9090", "external-controller: 127.0.0.1:9090/secret", "external-controller: 127.0.0.1:0", "external-controller: 127.0.0.1:65536", "  external-controller: 127.0.0.1:9090", "external-controller: 127.0.0.1:9090\nexternal-controller: 127.0.0.1:19090"] {
    check(MetaControllerDiscovery.controllerPort(in: text) == nil, "unsafe or ambiguous controller is rejected")
}
let testRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("meta-config-path-check", isDirectory: true)
check(MetaControllerDiscovery.permittedConfigPath(testRoot.appendingPathComponent("test.yaml").path, root: testRoot), "generated config accepted under allowed directory")
check(!MetaControllerDiscovery.permittedConfigPath(testRoot.appendingPathComponent("../secret.yaml").path, root: testRoot), "config path cannot escape allowed directory")
var unknown = refreshed; unknown.stateKnown = false
check(!unknown.canAct && !Bridge.validates(url, snapshot: unknown), "unknown live port state disables widget action")
check(Bridge.authenticates(url, snapshot: unknown), "cached credential can recover after host obtains fresh state")
check(!Bridge.authenticates(URL(string: "clash-meta-switch://apply/forged")!, snapshot: unknown), "unknown state never bypasses authentication")
print("Passed \(checks) security and proxy-state checks; no system settings modified.")
