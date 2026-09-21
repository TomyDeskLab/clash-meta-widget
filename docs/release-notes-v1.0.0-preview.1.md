> **已知故障，暂不推荐安装或分享此版本。** 用户实际使用已确认：构建 7 的旧卡片链接可能失效，点击时反复打开管理窗口。此前通过的是宿主 URL 入口测试，未覆盖桌面缓存卡片。构建 8 正在本机验收；此页面 ZIP 尚未更新，勿将旧包当作已修复版本。

以下为首个公开预览版的原始说明。下载包不需要安装 Xcode。

[不用 Xcode 的分步安装教程](https://github.com/YL-SSSSu/clash-meta-widget/blob/main/docs/安装教程.md) · [两种安装方式的测试报告](https://github.com/YL-SSSSu/clash-meta-widget/blob/main/docs/TEST_REPORT.md)

功能：

- macOS 原生 WidgetKit 小组件；
- 小号系统代理开关；
- 中号节点前后切换、规则／全局／直连与系统代理开关；
- Apple 芯片与 Intel 通用二进制，最低 macOS 14；
- 可设置系统代理端口、Meta 控制接口端口和可选 Bearer 密钥；
- 密钥只保存于 macOS 钥匙串。

该 ZIP 使用本机临时签名，没有 Apple Developer ID 公证。首次运行时 macOS 会提示无法验证开发者；请在“系统设置 → 隐私与安全性”中核对应用名称后选择“仍要打开”。不建议用 `xattr` 删除隔离属性。

SHA-256 请以同一 Release 中的 `SHA256SUMS.txt` 为准。安全范围、已验证项目和限制见仓库中的 `SECURITY.md` 与 `使用与实现说明.md`。

2026-09-21 复测：从 GitHub 下载的本包和干净源码经 Command Line Tools 构建的 App，在测试机上均通过系统代理、三种模式、节点切换与恢复。直接点按桌面卡片、全新 Mac 首次安装、Intel 实机及旧版 macOS 尚未完成验证。此版本继续标为预览版；安装教程已说明首次安全确认步骤。
