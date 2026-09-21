# Clash Meta Widget for macOS

一个放在 macOS 桌面上的原生 WidgetKit 小组件，用来控制已经运行的 ClashX Meta。

> 2026-09-21 更新：公开下载的 preview.1（构建 7）已确认有旧卡片点击失效、反复弹窗的问题，暂不推荐安装或继续分享。构建 8 修正了缓存链接和弹窗逻辑，已在本机安装并通过重复操作测试；桌面实际点按仍待验收，尚未发布新 ZIP。详见 [修复记录](./docs/build8修复记录.md)。

- 小号：开启或关闭系统代理。
- 中号：开启或关闭系统代理、切换上一个／下一个节点、切换规则／全局／直连模式。
- 原生桌面组件：由 macOS 管理位置、尺寸、外观和刷新，不是置顶悬浮窗。
- 本机控制：只连接 `127.0.0.1`，不读取订阅地址、节点服务器参数、密码或流量内容。
- 通用构建：支持 Apple 芯片和 Intel，最低 macOS 14。
- 可配置：系统代理端口、Meta External Controller 端口，以及可选 API 密钥。

> 当前版本只适配 bundle identifier 为 `com.metacubex.ClashX.meta` 的 ClashX Meta。它不控制 TUN，不负责启动或替换 ClashX Meta。

## 安装

第一次安装建议看 [不用 Xcode 的分步教程](./docs/安装教程.md)。两种路线的验证结果见 [测试报告](./docs/TEST_REPORT.md)。

待修复包发布后，可从 [GitHub Releases](https://github.com/YL-SSSSu/clash-meta-widget/releases) 下载预编译 ZIP，无需 Xcode；当前 preview.1 存在上述故障，不推荐安装。预览包使用本机临时签名，没有 Apple Developer ID 公证；首次运行可能被 macOS 阻止。请核对来源后按系统安全设置处理，项目不建议用 `xattr` 删除隔离属性。

也可以尝试从源码构建。以下 Command Line Tools 路线已验证编译与宿主入口，但构建 8 的桌面完整功能尚未按此路线复测，暂不将其视为已验收安装方法：

```bash
xcode-select --install
```

安装完成后：

```bash
git clone https://github.com/YL-SSSSu/clash-meta-widget.git
cd clash-meta-widget
bash script/install.sh
```

安装脚本把应用放入 `/Applications/Clash Meta Switch.app`。若已安装旧版，会先把旧版移入废纸篓并保留带时间的文件名，不会直接删除，也避免系统同时发现两个相同的小组件扩展。

打开一次 `Clash Meta Switch`，然后：

1. 在桌面空白处右键，选择“编辑小组件”。
2. 搜索 `Clash Meta` 或 `Clash Meta Switch`。
3. 添加中号组件。已经添加的小号组件可右键改为中号。
4. 构建 8 默认无窗口，在后台同步状态。

默认系统代理端口是 `7890`，External Controller 端口是 `9090`。如果配置不同，或控制接口设置了 `secret`，运行 `open 'clash-meta-switch://settings'` 主动打开设置，再展开“兼容设置”。桌面按钮不会调用设置窗口。密钥只保存在 macOS 钥匙串。

更完整的操作、架构、边界与故障排查见 [使用与实现说明](./使用与实现说明.md)，安全检查见 [SECURITY.md](./SECURITY.md)。

## 构建与验证

不使用 Xcode，只使用 Command Line Tools：

```bash
bash build-lite.sh
```

如果已经安装完整 Xcode，也可以走 Xcode 工程构建：

```bash
bash build.sh
```

脚本会：

1. 生成最小 Xcode 工程；
2. 构建 arm64 + x86_64 通用 Release 应用；
3. 验证代码签名结构；
4. 运行不会修改网络设置的安全与代理状态检查。

两种产物分别位于：

```text
build/native/Build/Products/Release/Clash Meta Switch.app
build/lite/Clash Meta Switch.app
```

本项目仅使用 Apple 系统框架，没有 Swift Package、CocoaPods、下载型构建步骤或第三方二进制依赖。`build-lite.sh` 已在 `DEVELOPER_DIR=/Library/Developer/CommandLineTools` 的工具链下验证，不调用 `xcodebuild`。

维护者可执行 `bash script/package-release.sh` 生成 ZIP 和 SHA-256 校验文件。

`docs/github-actions-build.yml` 提供了最小 GitHub Actions 模板。仓库维护者确认工作流权限和账单设置后，可将它复制到 `.github/workflows/build.yml` 启用；默认不自动运行第三方托管构建。

## 工作方式

WidgetKit 扩展没有网络权限，只读一个权限为 `0600` 的本地状态快照。点击小组件时，macOS 把带随机凭据的 URL 交给宿主；宿主校验后，通过 ClashX Meta 官方 AppleScript 切换系统代理，或通过固定到 `127.0.0.1` 的 Meta API 切换模式和节点。每次操作后重新读取实际状态确认。构建 8 的凭据在刷新和操作后保持稳定，允许缓存卡片重复使用；它不是一次性凭据，泄露后需要撤销，详见安全说明。

当前采用 `Link` / `widgetURL`，因为本地临时签名的 App Intent 在测试机上无法被系统正确执行。界面仍是原生 WidgetKit；点击动作会唤起宿主进程，macOS 可能产生前台激活或焦点变化。

## 已验证范围

- 构建 8 的 52 项输入与状态检查通过，覆盖缓存卡片重复使用、凭据撤销、伪造、跨动作凭据、非法节点、异常路径、端口边界、其他代理与 PAC/WPAD。
- 节点切换与恢复，以及规则、全局、直连三种模式，均通过与组件相同的 URL 入口实测，并重新读取 Meta 确认。
- WidgetKit 扩展在运行日志中确认可以读取状态快照。
- 2026-09-21 重新下载 Release ZIP 与干净源码 CLT 构建，两种 App 安装后均通过节点、三种模式和系统代理开关实测，测试后恢复原设置。
- 仍需要不同 macOS 版本、不同 Meta 配置、首次下载放行和真实桌面点击的社区测试。系统注册成功、宿主控制成功不等于桌面点击已完成验证。

## 开源与贡献

本项目采用 [MIT License](./LICENSE)。提交问题前请阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)，安全问题请按 [SECURITY.md](./SECURITY.md) 的方式私下报告，不要在 Issue 中附上订阅、密钥或完整操作 URL。

项目参考了 ClashX Meta 的官方快捷命令和 Meta 控制接口文档。曾研究 GPL-3.0 的 Hako-Client WidgetKit 结构，但本项目没有复制、静态链接或包含其源码、内核与资源。
