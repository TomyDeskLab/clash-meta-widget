import Foundation

// Opt-in live test: sends a small HTTP probe through one already selected node.
// It never changes a selector, proxy mode, system proxy, or endpoint settings.
@main struct DelaySmoke {
    static func main() async throws {
        let before = try await CoreAPI.proxies()
        let mode = try await CoreAPI.mode()
        var node = Bridge.read()?.group ?? "GLOBAL"
        var visited = Set<String>()
        while let next = before[node]?.now, visited.insert(node).inserted { node = next }
        guard before[node] != nil else { throw CoreError.invalidSelection }
        let delay = try await CoreAPI.delay(node)
        let after = try await CoreAPI.proxies()
        for (name, value) in before where value.type == "Selector" {
            guard after[name]?.now == value.now else { throw CoreError.verification }
        }
        guard try await CoreAPI.mode() == mode else { throw CoreError.verification }
        print("Live latency: \(delay) ms. All Selector choices and mode unchanged.")
    }
}
