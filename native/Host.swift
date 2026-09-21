import SwiftUI
import WidgetKit
import AppKit

@MainActor final class Controller: ObservableObject {
    static let shared = Controller()
    @Published var snapshot = Bridge.read()
    @Published var message = "桌面组件选中号：左右箭头换节点，下方按钮切换模式。此窗口可以关闭。"
    @Published var busy = false
    @Published var proxies: [String: ProxyItem] = [:]
    @Published var selectedGroup = UserDefaults.standard.string(forKey: "selectedGroup") ?? ""
    @Published var search = ""
    @Published var proxyPortText = String(AppSettings.proxyPort)
    @Published var socksPortText = String(AppSettings.socksPort)
    @Published var controlPortText = String(AppSettings.manualControlPort)
    @Published var automaticPorts = AppSettings.automaticPorts
    @Published var portSummary = "等待读取 Meta 运行端口…"
    @Published var apiSecret = AppSettings.apiSecret()
    @Published var delays: [String: DelayResult] = [:]
    @Published var testingNodes = Set<String>()
    @Published var delayProgress = ""
    private var delayTask: Task<Void, Never>?
    var testingDelays: Bool { delayTask != nil }
    private var refreshing = false
    private var loadedCore = false
    private var coreOnline = false
    private var mode: String?
    private var actionError: String?
    private var connectionFailed = false
    private var lastAction = Date.distantPast
    var groups: [String] { proxies.keys.filter { proxies[$0]?.type == "Selector" }.sorted() }
    var options: [String] {
        (proxies[selectedGroup]?.all ?? []).filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
    }
    var selectedNode: String? { proxies[selectedGroup]?.now }
    func canTest(_ node: String) -> Bool {
        guard let proxy = proxies[node] else { return false }
        return !["Reject", "REJECT", "Pass", "PASS"].contains(proxy.type)
    }
    func delayResult(_ node: String) -> DelayResult? {
        if let result = delays[node] { return result }
        guard let last = proxies[node]?.history?.last else { return nil }
        return last.delay > 0 ? .measured(last.delay) : .failed
    }
    func startDelayTests(_ names: [String]) {
        guard delayTask == nil, snapshot?.coreOnline == true else { return }
        let names = Array(Set(names.filter { canTest($0) })).sorted()
        guard !names.isEmpty else { return }
        testingNodes = Set(names)
        delayProgress = "测速 0/\(names.count)"
        delayTask = Task {
            var completed = 0
            // Process bounded batches of three; cancellation propagates to all probes.
            for start in stride(from: 0, to: names.count, by: 3) {
                if Task.isCancelled { break }
                async let first = CoreAPI.measureDelay(names[start])
                async let second = CoreAPI.measureDelay(start + 1 < names.count ? names[start + 1] : nil)
                async let third = CoreAPI.measureDelay(start + 2 < names.count ? names[start + 2] : nil)
                let results = await [first, second, third]
                if Task.isCancelled { break }
                for case let (name, result)? in results {
                    delays[name] = result
                    testingNodes.remove(name)
                    completed += 1
                    delayProgress = "测速 \(completed)/\(names.count)"
                }
            }
            delayProgress = Task.isCancelled ? "测速已停止" : "测速完成 · \(completed) 项"
            testingNodes.removeAll()
            delayTask = nil
        }
    }
    func cancelDelayTests() { delayTask?.cancel() }
    func copyDiagnostics() {
        let meta = NSRunningApplication.runningApplications(withBundleIdentifier: "com.metacubex.ClashX.meta").first
        let version = meta?.bundleURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String } ?? "未运行或未知"
        let report = """
        Clash Meta Widget 诊断
        组件构建：\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知")
        macOS：\(ProcessInfo.processInfo.operatingSystemVersionString)
        ClashX Meta：\(version)
        端口模式：\(AppSettings.automaticPorts ? "自动" : "手动")
        端口信息：\(portSummary)
        控制接口可达：\(snapshot?.coreOnline == true ? "是" : "否")
        当前代理：\(ProxyState.read()?.diagnosticSummary ?? "无法读取")
        上次操作错误：\(snapshot?.actionError ?? "无")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        message = "已复制诊断：仅包含版本、代理开关、端口与错误；不含节点、订阅、密钥或操作链接。"
    }
    func chooseGroup(_ name: String) {
        selectedGroup = name
        UserDefaults.standard.set(name, forKey: "selectedGroup")
        try? publish()
    }
    private func displayedNode() -> String? {
        var name = proxies[selectedGroup]?.now
        var seen = Set<String>()
        while let current = name, seen.insert(current).inserted, let next = proxies[current]?.now { name = next }
        return name
    }
    func publish(force: Bool = false) throws {
        let state = ProxyState.read()
        let old = Bridge.read()
        let currentMode = loadedCore ? mode : old?.mode
        let currentNode = loadedCore ? displayedNode() : old?.node
        let online = loadedCore ? coreOnline : old?.coreOnline == true
        let currentGroup = loadedCore ? selectedGroup : old?.group
        let currentSelection = loadedCore ? proxies[selectedGroup]?.now : old?.selection
        let choices = loadedCore ? (proxies[selectedGroup]?.all ?? []) : old?.nodeOptions
        let changed = old?.enabled != state?.enabled || old?.foreignProxy != state?.foreignProxy || old?.stateKnown != (state != nil) || old?.running != ProxyControl.isRunning || old?.mode != currentMode || old?.node != currentNode || old?.group != currentGroup || old?.coreOnline != online || old?.nodeOptions != choices || old?.selection != currentSelection
        var modeTickets = old?.modeTickets ?? [:]
        for name in ["rule", "global", "direct"] where modeTickets[name] == nil { modeTickets[name] = try Bridge.randomTicket() }
        let current = Snapshot(date: Date(), enabled: state?.enabled ?? false, foreignProxy: state?.foreignProxy ?? false,
                               running: ProxyControl.isRunning, ticket: try old?.ticket ?? Bridge.randomTicket(),
                               expires: Date.distantFuture,
                               targetEnabled: !(state?.enabled ?? false), mode: currentMode, node: currentNode, group: currentGroup,
                               coreOnline: online, modeTickets: modeTickets, nodeOptions: choices,
                               nodeTicket: try old?.nodeTicket ?? Bridge.randomTicket(), selection: currentSelection,
                               actionError: actionError, stateKnown: state != nil)
        if force || changed || old == nil || old?.actionError != actionError || Date().timeIntervalSince(old!.date) > 300 {
            try Bridge.write(current)
            WidgetCenter.shared.reloadAllTimelines()
        }
        snapshot = current
    }
    private func loadConnection() async throws -> CoreConfiguration {
        if AppSettings.automaticPorts {
            AppSettings.detectedControlPort = await MetaControllerDiscovery.discover()
        }
        do {
            let config = try await CoreAPI.configuration()
            if AppSettings.automaticPorts {
                guard let ports = config.proxyPorts else { throw CoreError.unknownPorts }
                AppSettings.detectedProxyPorts = ports
            }
            let source = AppSettings.automaticPorts ? (AppSettings.detectedControlPort == nil ? "备用控制接口" : "自动发现控制接口") : "手动控制接口"
            portSummary = "\(AppSettings.proxyPorts?.summary ?? "端口未知") · \(source) \(AppSettings.controlPort)"
            if connectionFailed { actionError = nil; connectionFailed = false }
            return config
        } catch {
            AppSettings.detectedProxyPorts = nil
            connectionFailed = true
            portSummary = "读取失败 · 控制接口 \(AppSettings.controlPort)；请检查 Meta 或兼容设置。"
            throw error
        }
    }
    private func loadCore() async throws {
        let m = try await loadConnection().mode
        let p = try await CoreAPI.proxies()
        mode = m; proxies = p; coreOnline = true; loadedCore = true
        if m == "global", p["GLOBAL"]?.type == "Selector" { selectedGroup = "GLOBAL" }
        else if !groups.contains(selectedGroup) || (m == "rule" && selectedGroup == "GLOBAL") {
            selectedGroup = groups.first(where: { $0 != "GLOBAL" && !(p[$0]?.now == "DIRECT") }) ?? groups.first ?? ""
        }
    }
    func refresh(reportError: Bool = false) async {
        guard !busy, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do { try await loadCore(); try publish() }
        catch {
            coreOnline = false; loadedCore = true
            if AppSettings.automaticPorts && AppSettings.detectedProxyPorts == nil { actionError = error.localizedDescription }
            try? publish()
            if reportError { message = error.localizedDescription }
        }
    }
    private func checkLocalState() throws {
        guard ProxyControl.isRunning else { throw SwitchError.notRunning }
        guard let state = ProxyState.read() else { throw SwitchError.unknownState }
        guard !state.foreignProxy else { throw SwitchError.otherProxy }
    }
    func apply(_ url: URL) async {
        guard !busy, Date().timeIntervalSince(lastAction) > 0.8 else { return }
        busy = true
        defer { busy = false }
        while refreshing { try? await Task.sleep(for: .milliseconds(50)) }
        do {
            guard let prior = Bridge.read(), Bridge.authenticates(url, snapshot: prior) else { throw BridgeError.expired }
            guard ProxyControl.isRunning else { throw SwitchError.notRunning }
            if AppSettings.automaticPorts || url.host != "apply" { _ = try await loadConnection() }
            try checkLocalState()
            lastAction = Date()
            actionError = nil
            // Re-read actual state: a cached desktop card is not a target-state command.
            if url.host == "apply" {
                guard let state = ProxyState.read() else { throw SwitchError.unknownState }
                try await ProxyControl.setEnabled(!state.enabled)
            }
            else if url.host == "previous" || url.host == "next" {
                try await loadCore()
                guard let selector = proxies[selectedGroup], selector.type == "Selector",
                      let choices = selector.all, !choices.isEmpty,
                      let index = choices.firstIndex(of: selector.now ?? "") else { throw CoreError.invalidSelection }
                let offset = url.host == "previous" ? -1 : 1
                try await CoreAPI.setNode(choices[(index + offset + choices.count) % choices.count], group: selectedGroup)
            }
            else if url.host == "node", let node = Bridge.nodeName(from: url, snapshot: prior), let group = prior.group {
                try await CoreAPI.setNode(node, group: group)
            }
            else { try await CoreAPI.setMode(url.host!) }
            do { try await loadCore() } catch { coreOnline = false; loadedCore = true }
            try publish(force: true)
            message = "已确认切换成功，桌面状态由系统刷新。"
        } catch {
            message = error.localizedDescription
            actionError = message
            try? publish(force: true)
        }
    }
    func selectNode(_ node: String) async {
        guard !busy, !refreshing else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await loadConnection()
            try checkLocalState()
            let group = selectedGroup
            try await CoreAPI.setNode(node, group: group)
            try await loadCore()
            try publish(force: true)
            message = "已确认「\(group)」选择：\(node)"
        } catch { message = error.localizedDescription; try? publish(force: true) }
    }
    func openAction(_ url: URL?) { if let url { NSWorkspace.shared.open(url) } }
    func saveConnectionSettings() async {
        guard !busy, !refreshing else { return }
        guard let proxy = Int(proxyPortText), let socks = Int(socksPortText), let control = Int(controlPortText),
              AppSettings.validPort(proxy) != nil, AppSettings.validPort(socks) != nil, AppSettings.validPort(control) != nil else {
            message = CoreError.invalidSettings.localizedDescription
            return
        }
        do {
            try AppSettings.saveAPISecret(apiSecret)
            AppSettings.automaticPorts = automaticPorts
            AppSettings.savePorts(proxy: proxy, socks: socks, control: control)
            delays.removeAll()
            loadedCore = false
            message = "设置已保存；控制接口密钥仅保存在 macOS 钥匙串。"
            await refresh(reportError: true)
        } catch { message = error.localizedDescription }
    }
}

struct SettingsView: View {
    @ObservedObject var controller = Controller.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Clash Meta").font(.title2.bold())
                Spacer()
                if let snapshot = controller.snapshot {
                    Button(snapshot.enabled ? "关闭系统代理" : "开启系统代理") { controller.openAction(snapshot.actionURL) }
                        .disabled(controller.busy || !snapshot.canAct)
                }
            }
            Text(controller.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                ForEach(["rule", "global", "direct"], id: \.self) { mode in
                    Button {
                        controller.openAction(controller.snapshot?.modeURL(mode))
                    } label: {
                        Label(modeName(mode), systemImage: controller.snapshot?.mode == mode ? "checkmark.circle.fill" : "circle")
                    }.disabled(controller.busy || controller.snapshot?.modeURL(mode) == nil)
                }
            }
            Divider()
            if controller.snapshot?.coreOnline == true {
                Picker("策略组", selection: Binding(get: { controller.selectedGroup }, set: { controller.chooseGroup($0) })) {
                    ForEach(controller.groups, id: \.self) { Text($0).tag($0) }
                }.disabled(controller.busy)
                TextField("搜索节点", text: $controller.search).textFieldStyle(.roundedBorder)
                HStack {
                    Text("连接延迟").font(.caption).foregroundStyle(.secondary)
                    Text(controller.delayProgress).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if controller.testingDelays {
                        Button("停止") { controller.cancelDelayTests() }
                    } else {
                        Button("测当前列表") { controller.startDelayTests(controller.options) }
                            .disabled(controller.options.filter { controller.canTest($0) }.isEmpty)
                    }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(controller.options, id: \.self) { node in
                            HStack(spacing: 8) {
                                Button { Task { await controller.selectNode(node) } } label: {
                                    HStack {
                                    Image(systemName: controller.selectedNode == node ? "checkmark.circle.fill" : "circle").foregroundStyle(controller.selectedNode == node ? Color.accentColor : .secondary)
                                    Text(node).lineLimit(1)
                                    Spacer()
                                    if let type = controller.proxies[node]?.type, ["URLTest", "Fallback", "Selector"].contains(type) { Text("策略组").font(.caption).foregroundStyle(.secondary) }
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain).disabled(controller.busy)
                                Button { controller.startDelayTests([node]) } label: {
                                    Text(controller.testingNodes.contains(node) ? "测速中…" : controller.delayResult(node)?.label ?? "测速")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(delayColor(node)).frame(width: 78, alignment: .trailing)
                                        .padding(.vertical, 4).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .disabled(controller.testingDelays || !controller.canTest(node))
                                    .help("点击测试此节点到 Google 204 的连接延迟；不切换节点")
                                    .accessibilityLabel("测速 \(node)，\(controller.delayResult(node)?.label ?? "未测试")")
                            }.padding(.horizontal, 10).padding(.vertical, 5)
                        }
                    }
                }.frame(height: 215)
                Text("延迟单位 ms，点击数值可重测；打开时可显示 Meta 已有记录。")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("节点列表暂不可用，请确认 Meta 已运行后刷新。").foregroundStyle(.secondary).frame(height: 120)
            }
            Text("规则模式按规则分流；全局模式使用 GLOBAL 策略组；直连模式不使用代理。系统代理开关不控制 TUN。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("兼容设置") {
                Toggle("自动读取 Meta 端口（推荐）", isOn: $controller.automaticPorts)
                Text(controller.portSummary).font(.caption).textSelection(.enabled)
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    if !controller.automaticPorts {
                        GridRow { Text("HTTP/HTTPS 端口"); TextField("7890", text: $controller.proxyPortText).frame(width: 90) }
                        GridRow { Text("SOCKS 端口"); TextField("7890", text: $controller.socksPortText).frame(width: 90) }
                    }
                    GridRow { Text(controller.automaticPorts ? "备用控制接口端口" : "控制接口端口"); TextField("9090", text: $controller.controlPortText).frame(width: 90) }
                    GridRow { Text("接口密钥"); SecureField("未设置", text: $controller.apiSecret).frame(width: 210) }
                }.textFieldStyle(.roundedBorder)
                Button("保存并重新读取") { Task { await controller.saveConnectionSettings() } }.disabled(controller.testingDelays || controller.busy)
                Text("控制地址固定为本机 127.0.0.1；密钥只存入钥匙串。留空表示接口未设置密钥。").font(.caption).foregroundStyle(.secondary)
            }.font(.callout)
            HStack {
                Button("刷新") { Task { await controller.refresh(reportError: true) } }.disabled(controller.busy)
                Button("复制诊断") { controller.copyDiagnostics() }
                Spacer()
                Button("关闭窗口") { Delegate.shared?.window?.close() }
            }
        }.padding(22).frame(width: 430)
    }
    private func modeName(_ mode: String) -> String { ["rule": "规则", "global": "全局", "direct": "直连"][mode]! }
    private func delayColor(_ node: String) -> Color {
        if controller.testingNodes.contains(node) { return .secondary }
        guard let result = controller.delayResult(node) else { return .secondary }
        switch result {
        case .measured(let value): return value < 200 ? .green : value < 500 ? .orange : .red
        case .failed: return .red
        }
    }
}

@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    static weak var shared: Delegate?
    var window: NSWindow?
    var handledURL = false
    var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        do { try Controller.shared.publish() } catch { Controller.shared.message = error.localizedDescription }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in await Controller.shared.refresh() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if CommandLine.arguments.contains("--settings") { self.showWindow() }
            Task { await Controller.shared.refresh() }
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.count == 1, let url = urls.first, url.scheme == "clash-meta-switch" else { return }
        handledURL = true
        if url.absoluteString == "clash-meta-switch://settings" {
            // Only the explicit Settings link opens a window; proxy actions stay silent.
            showWindow()
            Task { await Controller.shared.refresh(reportError: true) }
        } else if url.absoluteString == "clash-meta-switch://controls" {
            Task { await Controller.shared.refresh(reportError: true) }
        } else { Task { await Controller.shared.apply(url) } }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { false }
    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 474, height: 680), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Clash Meta 节点与模式"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

@main struct MetaSwitchApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    var body: some Scene { Settings { SettingsView() } }
}
