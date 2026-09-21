import SwiftUI
import WidgetKit
import OSLog

struct Entry: TimelineEntry { let date: Date; let snapshot: Snapshot? }
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: Date(), snapshot: Bridge.read())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snapshot = Bridge.read()
        Logger(subsystem: "local.clash.metaswitch", category: "widget").notice("Snapshot readable: \(snapshot != nil), enabled: \(snapshot?.enabled == true)")
        completion(Timeline(entries: [Entry(date: Date(), snapshot: snapshot)], policy: .after(Date().addingTimeInterval(300))))
    }
}
struct SwitchView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry
    private let controls = URL(string: "clash-meta-switch://controls")!
    var status: String {
        guard let snapshot = entry.snapshot else { return "请打开应用初始化" }
        if !snapshot.running { return "ClashX Meta 未运行" }
        if snapshot.foreignProxy { return "检测到其他代理" }
        if snapshot.actionError != nil { return "操作未完成，请查看提示" }
        return snapshot.enabled ? "系统代理已开启" : "系统代理已关闭"
    }
    var power: some View {
        Image(systemName: "power").font(.system(size: 23, weight: .medium)).foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .background(Color.blue.opacity(0.18), in: Circle())
            .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
            .accessibilityLabel(entry.snapshot?.enabled == true ? "关闭系统代理" : "开启系统代理")
    }
    private var nodeChoices: [String] { entry.snapshot?.nodeOptions ?? [] }
    private var nodeIndex: Int { nodeChoices.firstIndex(of: entry.snapshot?.selection ?? entry.snapshot?.node ?? "") ?? 0 }
    private func adjacentNode(_ offset: Int) -> String? {
        guard !nodeChoices.isEmpty else { return nil }
        return nodeChoices[(nodeIndex + offset + nodeChoices.count) % nodeChoices.count]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Circle().fill(entry.snapshot?.enabled == true ? Color.green : Color.gray).frame(width: 7, height: 7)
                        Text(status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Text("Clash").font(.system(size: 23, weight: .bold, design: .rounded))
                }
                Spacer(minLength: 0)
                if family == .systemMedium {
                    Link(destination: entry.snapshot?.actionURL ?? controls) { power }
                }
            }
            if family == .systemMedium {
                HStack(spacing: 8) {
                    if let previous = adjacentNode(-1), let url = entry.snapshot?.stepURL(-1) {
                        Link(destination: url) { Image(systemName: "chevron.left").frame(width: 26, height: 26).background(.secondary.opacity(0.1), in: Circle()) }
                            .accessibilityLabel("上一个节点：\(previous)")
                    }
                    Text(entry.snapshot?.node ?? "节点不可用").font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: .infinity)
                    if let next = adjacentNode(1), let url = entry.snapshot?.stepURL(1) {
                        Link(destination: url) { Image(systemName: "chevron.right").frame(width: 26, height: 26).background(.secondary.opacity(0.1), in: Circle()) }
                            .accessibilityLabel("下一个节点：\(next)")
                    }
                }.foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text(entry.snapshot?.actionError ?? (entry.snapshot?.coreOnline == true ? "Meta · 这台 Mac" : "Meta 控制接口未连接"))
                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 0)
                    Link(destination: URL(string: "clash-meta-switch://settings")!) {
                        Label("设置", systemImage: "gearshape")
                            .font(.system(size: 10)).padding(.horizontal, 6).padding(.vertical, 3)
                            .contentShape(Rectangle())
                    }.foregroundStyle(.primary)
                        .accessibilityLabel("手动打开节点与模式设置")
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(["rule", "global", "direct"], id: \.self) { mode in
                        Link(destination: entry.snapshot?.modeURL(mode) ?? controls) {
                            Text(["rule": "规则", "global": "全局", "direct": "直连"][mode]!)
                                .font(.system(size: 11, weight: entry.snapshot?.mode == mode ? .bold : .regular))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(entry.snapshot?.mode == mode ? Color.blue.opacity(0.25) : Color.secondary.opacity(0.1), in: Capsule())
                                .overlay(Capsule().strokeBorder(.primary.opacity(entry.snapshot?.mode == mode ? 0.45 : 0.12), lineWidth: 1))
                        }.foregroundStyle(.primary)
                    }
                    Spacer(minLength: 0)
                    if let date = entry.snapshot?.date { Text(date, style: .time).font(.system(size: 9)).foregroundStyle(.secondary) }
                }
            } else {
                Text(entry.snapshot?.actionError ?? entry.snapshot?.node ?? "Meta · 这台 Mac").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.snapshot?.enabled == true ? "点按关闭" : "点按开启").font(.system(size: 10))
                        if let date = entry.snapshot?.date { Text(date, style: .time).font(.system(size: 9)).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                    power
                }
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(family == .systemMedium ? nil : entry.snapshot?.actionURL ?? controls)
    }
}
@main struct MetaSwitchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MetaProxySwitch", provider: Provider()) { SwitchView(entry: $0) }
            .configurationDisplayName("Clash Meta")
            .description("控制本机 Meta 系统代理。中号可直接切换节点、规则、全局和直连。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
