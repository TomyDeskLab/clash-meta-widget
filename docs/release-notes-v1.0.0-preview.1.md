首个公开预览版。下载 ZIP、解压并移入“应用程序”即可使用，不需要安装 Xcode。

功能：

- macOS 原生 WidgetKit 小组件；
- 小号系统代理开关；
- 中号节点前后切换、规则／全局／直连与系统代理开关；
- Apple 芯片与 Intel 通用二进制，最低 macOS 14；
- 可设置系统代理端口、Meta 控制接口端口和可选 Bearer 密钥；
- 密钥只保存于 macOS 钥匙串。

该 ZIP 使用本机临时签名，没有 Apple Developer ID 公证。首次运行时 macOS 会提示无法验证开发者；请在“系统设置 → 隐私与安全性”中核对应用名称后选择“仍要打开”。不建议用 `xattr` 删除隔离属性。

SHA-256 请以同一 Release 中的 `SHA256SUMS.txt` 为准。安全范围、已验证项目和限制见仓库中的 `SECURITY.md` 与 `使用与实现说明.md`。
