import Foundation
import AppKit

// Only the host app compiles this file. The widget cannot execute Apple Events.
enum SwitchError: LocalizedError {
    case notRunning, otherProxy, busy, denied, failed, unknownState
    case commandFailed(Int), stateTimeout(Bool, String)
    var errorDescription: String? {
        switch self {
        case .notRunning: "请先启动现有的 ClashX Meta。"
        case .otherProxy: "检测到其他代理或 PAC。为避免覆盖，请先在相应客户端中关闭。"
        case .busy: "代理切换正在进行，请稍后再试。"
        case .denied: "请在系统设置 → 隐私与安全性 → 自动化中允许 Clash Meta Switch 控制 ClashX Meta。"
        case .failed: "无法创建 Meta 控制命令（P01）；未发送切换命令。"
        case .commandFailed(let code): "Meta 控制命令返回错误 \(code)（P02）。请复制诊断信息；不要连续重试开关。"
        case .stateTimeout(let target, let state): "已发送\(target ? "开启" : "关闭")请求，但 10 秒内未确认（P03）。请先在 Meta 菜单核对实际状态，再复制诊断信息。\(state)"
        case .unknownState: "无法读取系统代理状态；未更改代理。"
        }
    }
}

@MainActor enum ProxyControl {
    private static var busy = false
    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: "com.metacubex.ClashX.meta").isEmpty }
    static func setEnabled(_ value: Bool) async throws {
        guard !busy else { throw SwitchError.busy }
        busy = true
        defer { busy = false }
        guard isRunning else { throw SwitchError.notRunning }
        guard let before = ProxyState.read() else { throw SwitchError.unknownState }
        guard !before.foreignProxy else { throw SwitchError.otherProxy }
        guard before.enabled != value else { return }
        // The script is a compile-time constant, with no external string interpolation.
        guard let script = NSAppleScript(source: "tell application id \"com.metacubex.ClashX.meta\" to toggleProxy") else { throw SwitchError.failed }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            if error[NSAppleScript.errorNumber] as? Int == -1743 { throw SwitchError.denied }
            throw SwitchError.commandFailed(error[NSAppleScript.errorNumber] as? Int ?? 0)
        }
        // Meta's helper applies network preferences asynchronously. Observe longer,
        // but never retry toggleProxy: a second toggle could undo a delayed success.
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(200))
            if let after = ProxyState.read(), !after.foreignProxy, after.enabled == value { return }
        }
        throw SwitchError.stateTimeout(value, ProxyState.read()?.diagnosticSummary ?? "系统代理状态无法读取")
    }
}
