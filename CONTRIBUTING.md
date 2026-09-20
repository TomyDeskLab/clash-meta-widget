# Contributing

欢迎提交兼容性修复、可访问性改进和安全审查结果。请保持改动范围清晰，并说明测试过的 macOS 版本、Mac 架构、ClashX Meta 版本、系统代理端口与控制接口是否启用密钥。

提交 Pull Request 前运行：

```bash
bash build.sh
git diff --check
```

请勿提交以下内容：

- `build/`、DerivedData、签名证书或公证凭据；
- Clash 配置、订阅地址、节点服务器信息或 External Controller 密钥；
- 状态快照 `~/Library/Application Support/ClashMetaSwitch/snapshot.json`；
- 带完整一次性操作凭据的 `clash-meta-switch://` URL；
- 未说明来源和许可证的图像、代码或二进制文件。

普通缺陷可以提交 Issue。可能导致未授权代理切换、凭据泄露或沙盒越界的问题，请按照 `SECURITY.md` 私下报告。
