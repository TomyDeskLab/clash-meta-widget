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
print("Passed \(checks) security and proxy-state checks; no system settings modified.")
