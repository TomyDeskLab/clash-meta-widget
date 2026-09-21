# 构建 10：直接下载使用，无需 Xcode

下载下方 Assets 的 `Clash-Meta-Widget-1.0-build10-macos-universal.zip`，解压，把 App 拖进“应用程序”并打开一次，再到桌面右键 → 编辑小组件 → 添加 Clash Meta 中号组件。

不要选 `Source code` 作为安装包。安装、运行不需要 Xcode 或 Command Line Tools。

## 更新

- 修复旧卡片在刷新后操作链接失效的问题，开关按实时状态切换。
- 开关、节点和模式操作不再自动打开管理窗口；中号“⚙ 设置”可手动打开。
- 节点窗口支持搜索、选策略组、单节点延迟显示与测速、最多 3 项并发的批量测速及停止。
- 原生 macOS WidgetKit 卡片，支持小号与中号；不是悬浮窗。

最低 macOS 14，仅适配正在运行的 ClashX Meta。包内包含 Apple 芯片与 Intel 架构，本轮实际运行测试在 Apple 芯片 Mac 完成。

## 安装提示

当前为临时本地签名，**没有 Apple Developer ID 公证**，下载后首次启动可能被 macOS 阻止。核对来源后按系统提供的“隐私与安全性 → 仍要打开”处理；不要关闭系统安全保护。完整步骤见 [安装教程](https://github.com/YL-SSSSu/clash-meta-widget/blob/main/docs/安装教程.md)。

升级时移走旧 App 副本。构建 7 遗留的桌面卡片需移除后重新添加一次；已使用构建 8/9/10 的卡片通常无需重加。

## 实测范围

打包来源为本机已运行验证的构建 10 App；通过通用架构、签名完整性和 ZIP 解压一致性检查。已实点测试节点窗口的单节点测速、8 项批量测速和停止，确认代理开关、模式及节点选择不变。重复控制入口的回归测试也已通过。

桌面卡片全部按钮、全新 Mac 首次安装、Intel 实机和旧系统尚未完成完整验收，因此仍是预览版。点击使用稳定本地随机凭据，不再声称防重放；不要分享私有快照或完整操作 URL。见 [安全说明](https://github.com/YL-SSSSu/clash-meta-widget/blob/main/SECURITY.md)。

`SHA256SUMS.txt` 用于校验下载文件一致性，不等同于 Apple 公证。
