#!/bin/bash
# Read-only, allowlisted report. Does not invoke Meta, change proxies or read secrets.
set -eu
export LC_ALL=C

valid_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
setting() { /usr/bin/defaults read local.clash.metaswitch "$1" 2>/dev/null || true; }
proxy_port="$(setting proxyPort)"
valid_port "$proxy_port" || proxy_port=7890
control_port="${1:-$(setting controlPort)}"
if [[ -n "${1:-}" ]] && ! valid_port "$control_port"; then
    echo '控制接口端口应为 1–65535 的整数。' >&2
    exit 1
fi
valid_port "$control_port" || control_port=9090

echo '=== Clash Meta Widget 只读诊断 ==='
echo "macOS: $(/usr/bin/sw_vers -productVersion)"
echo "架构: $(/usr/bin/uname -m)"
app_version() {
    local value
    value="$(/usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$value" =~ ^[0-9A-Za-z.+_-]{1,40}$ ]]; then echo "$value"; else echo '未知（可能安装在其他位置）'; fi
}
echo "组件构建: $(app_version '/Applications/Clash Meta Switch.app' CFBundleVersion)"
echo "Meta 版本: $(app_version '/Applications/ClashX Meta.app' CFBundleShortVersionString)"
echo "组件保存的备用代理端口: $proxy_port（构建 10 将其用于全部协议；构建 11 默认自动读取）"
echo "本次检查的控制接口端口: $control_port"

echo '--- macOS 当前系统代理 ---'
# Read only top-level proxy settings. Never print remote hosts or PAC URLs.
/usr/sbin/scutil --proxy | /usr/bin/awk '
  /^  [A-Za-z]+ : / { values[$1]=$3 }
  END {
    split("HTTP HTTPS SOCKS", kinds, " ")
    for (i=1;i<=3;i++) {
      k=kinds[i]; on=(values[k "Enable"]==1)
      host=values[k "Proxy"]
      localHost=(host=="127.0.0.1" || host=="localhost" || host=="::1")
      port=values[k "Port"]
      if (port !~ /^[0-9]+$/) port="未知"
      if (on) printf "%s: 开; %s; 端口=%s\n", k, (localHost ? "本机" : "非本机或未知（地址隐藏）"), port
      else printf "%s: 关\n", k
    }
    printf "PAC: %s; WPAD: %s\n", (values["ProxyAutoConfigEnable"]==1 ? "开" : "关"), (values["ProxyAutoDiscoveryEnable"]==1 ? "开" : "关")
  }'

echo '--- Meta 控制接口的运行时端口 ---'
umask 077
response_file="$(/usr/bin/mktemp -t clash-widget-diagnostic)"
trap '/bin/rm -f "$response_file"' EXIT
# -q ignores curlrc; loopback only, no redirects, no proxy, no credentials.
status="$(/usr/bin/curl -q --noproxy '*' --connect-timeout 2 --max-time 4 --max-filesize 1048576 \
    -s -o "$response_file" -w '%{http_code}' "http://127.0.0.1:$control_port/configs" 2>/dev/null || true)"
case "$status" in
    200)
        for key in port socks-port mixed-port; do
            value="$(/usr/bin/plutil -extract "$key" raw -o - "$response_file" 2>/dev/null || true)"
            if [[ "$value" == 0 ]] || valid_port "$value"; then echo "$key: $value"; else echo "$key: 未返回有效端口"; fi
        done
        ;;
    401|403) echo '接口需要授权；本脚本不读取密钥。请另行提供 Meta 界面的端口数字。' ;;
    *) echo '接口未返回可用配置；这本身不能证明代理开关故障。请核对控制接口端口。' ;;
esac
echo '=== 完成：未修改设置；输出不含节点、订阅、密钥或操作链接 ==='
