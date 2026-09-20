# Clash Meta Widget for macOS

一个放在 macOS 桌面上的原生 WidgetKit 小组件，用来控制已经运行的 ClashX Meta。

- 小号：开启或关闭系统代理。
- 中号：开启或关闭系统代理、切换上一个／下一个节点、切换规则／全局／直连模式。
- 原生桌面组件：由 macOS 管理位置、尺寸、外观和刷新，不是置顶悬浮窗。
- 本机控制：只连接 `127.0.0.1`，不读取订阅地址、节点服务器参数、密码或流量内容。
- 通用构建：支持 Apple 芯片和 Intel，最低 macOS 14。
- 可配置：系统代理端口、Meta External Controller 端口，以及可选 API 密钥。

> 当前版本只适配 bundle identifier 为 `com.metacubex.ClashX.meta` 的 ClashX Meta。它不控制 TUN，不负责启动或替换 ClashX Meta。

## 安装

目前建议从源码构建，因为公开下载的未公证二进制会触发 macOS Gatekeeper。需要安装 Xcode 和 Python 3。

```bash
git clone https://github.com/YL-SSSSu/clash-meta-widget.git
cd clash-meta-widget
bash build.sh
bash script/install.sh --skip-build
```

安装脚本把应用放入 `/Applications/Clash Meta Switch.app`。若已安装旧版，会先把旧版移入废纸篓并保留带时间的文件名，不会直接删除，也避免系统同时发现两个相同的小组件扩展。

打开一次 `Clash Meta Switch`，然后：

1. 在桌面空白处右键，选择“编辑小组件”。
2. 搜索 `Clash Meta` 或 `Clash Meta Switch`。
3. 添加中号组件。已经添加的小号组件可右键改为中号。
4. 关闭说明窗口；宿主仍在后台同步状态。

默认系统代理端口是 `7890`，External Controller 端口是 `9090`。如果配置不同，或控制接口设置了 `secret`，在宿主窗口展开“兼容设置”后填写。密钥只保存在 macOS 钥匙串。

更完整的操作、架构、边界与故障排查见 [使用与实现说明](./使用与实现说明.md)，安全检查见 [SECURITY.md](./SECURITY.md)。

## 构建与验证

```bash
bash build.sh
```

脚本会：

1. 生成最小 Xcode 工程；
2. 构建 arm64 + x86_64 通用 Release 应用；
3. 验证代码签名结构；
4. 运行不会修改网络设置的安全与代理状态检查。

产物位于：

```text
build/native/Build/Products/Release/Clash Meta Switch.app
```

本项目仅使用 Apple 系统框架，没有 Swift Package、CocoaPods、下载型构建步骤或第三方二进制依赖。

`docs/github-actions-build.yml` 提供了最小 GitHub Actions 模板。仓库维护者确认工作流权限和账单设置后，可将它复制到 `.github/workflows/build.yml` 启用；默认不自动运行第三方托管构建。

## 工作方式

WidgetKit 扩展没有网络权限，只读一个权限为 `0600` 的本地状态快照。点击小组件时，macOS 把带一次性随机凭据的 URL 交给宿主；宿主校验后，通过 ClashX Meta 官方 AppleScript 切换系统代理，或通过固定到 `127.0.0.1` 的 Meta API 切换模式和节点。每次操作后重新读取实际状态确认。

当前采用 `Link` / `widgetURL`，因为本地临时签名的 App Intent 在测试机上无法被系统正确执行。界面仍是原生 WidgetKit；点击动作会唤起宿主进程，macOS 可能产生前台激活或焦点变化。

## 已验证范围

- 46 项输入与状态检查通过，包括伪造、过期、重放、跨动作凭据、非法节点、异常路径、端口边界、其他代理与 PAC/WPAD。
- 节点切换与恢复，以及规则、全局、直连三种模式，均通过与组件相同的 URL 入口实测，并重新读取 Meta 确认。
- WidgetKit 扩展在运行日志中确认可以读取状态快照。
- 仍需要不同 macOS 版本、不同 Meta 配置和真实桌面点击的社区测试。

## 开源与贡献

本项目采用 [MIT License](./LICENSE)。提交问题前请阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)，安全问题请按 [SECURITY.md](./SECURITY.md) 的方式私下报告，不要在 Issue 中附上订阅、密钥或完整操作 URL。

项目参考了 ClashX Meta 的官方快捷命令和 Meta 控制接口文档。曾研究 GPL-3.0 的 Hako-Client WidgetKit 结构，但本项目没有复制、静态链接或包含其源码、内核与资源。
