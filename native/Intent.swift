import Foundation
import AppKit

// Only the host app compiles this file. The widget cannot execute Apple Events.
enum SwitchError: LocalizedError {
    case notRunning, otherProxy, busy, denied, failed, unknownState
    var errorDescription: String? {
        switch self {
        case .notRunning: "请先启动现有的 ClashX Meta。"
        case .otherProxy: "检测到其他代理或 PAC。为避免覆盖，请先在相应客户端中关闭。"
        case .busy: "代理切换正在进行，请稍后再试。"
        case .denied: "请在系统设置 → 隐私与安全性 → 自动化中允许 Clash Meta Switch 控制 ClashX Meta。"
        case .failed: "代理状态未按预期改变。请在 ClashX Meta 中检查，并核对兼容设置中的系统代理端口。"
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
            throw SwitchError.failed
        }
        for _ in 0..<15 {
            try await Task.sleep(for: .milliseconds(200))
            if let after = ProxyState.read(), !after.foreignProxy, after.enabled == value { return }
        }
        throw SwitchError.failed
    }
}
