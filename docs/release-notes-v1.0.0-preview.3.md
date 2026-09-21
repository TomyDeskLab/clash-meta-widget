# 构建 11：自动读取 Meta 端口

下载下方 Assets 的 `Clash-Meta-Widget-1.0-build11-macos-universal.zip`，解压，把 App 拖进“应用程序”并打开一次，再到桌面右键 → 编辑小组件 → 添加 Clash Meta 中号组件。不要选 `Source code` 作为安装包；普通使用者不需要 Xcode。

## 本次修复

- 默认自动发现正在运行的 ClashX Meta 本机控制接口，并读取实际 HTTP、SOCKS 和混合端口。
- 混合端口启用时优先使用混合端口；否则分别识别 HTTP/HTTPS 与 SOCKS，解决旧版只认一个端口的兼容缺口。
- 启动、定时刷新和每次开关前重新确认端口。端口不变时无需手动修改；Meta 重启或换配置后会重新读取。
- 无法可靠识别端口时停止切换并显示错误，不根据猜测改系统代理。
- 保留手动兼容设置与备用控制接口端口；新增不含订阅、节点或密钥的“复制诊断”。
- 将 Meta 命令错误与状态确认超时分开显示，状态确认时间延长到 10 秒，且不会为了重试再次反转开关。

## 验证

- Release 通用构建与签名完整性检查通过，82 项输入、路径和代理状态检查通过。
- 故意把小组件保存的 HTTP、SOCKS 和控制接口端口全部设错后，仍自动发现 Meta，并完成四次真实开关。
- 临时切换为非默认混合端口及分开的 HTTP/SOCKS 端口，均成功读取；随后恢复原端口、组件设置、系统代理、模式和全部 Selector 选择。
- 缓存开关链接连续切换、模式切换、节点前进与伪造链接拒绝回归通过。

反馈者最初的“能开不能关”是否完全由端口差异造成，仍需其只读诊断结果确认；本版针对已经确认存在的端口兼容缺口进行了修复。桌面 WidgetKit 卡片的所有按钮、Intel 实机和旧版 macOS 仍未完成全面验收，因此继续标为预览版。

当前为本地临时签名，没有 Apple Developer ID 公证。完整步骤见[安装教程](https://github.com/TomyDeskLab/clash-meta-widget/blob/main/docs/安装教程.md)，安全边界见[安全说明](https://github.com/TomyDeskLab/clash-meta-widget/blob/main/SECURITY.md)。
