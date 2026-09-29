#!/bin/bash
# ClaudeMeter 开机自启动管理
#
# 用法：./login-item.sh install | uninstall | status
#
# 说明：这个 App 是本地编译的（未签名、未公证），macOS 的 SMAppService
# 不接受它注册登录项，所以这里用一个标准的用户级 LaunchAgent，
# 只装在你自己的 ~/Library/LaunchAgents 下，不碰系统目录。
#
# 没有设置 KeepAlive —— 你手动退出后不会被自动拉起。

set -euo pipefail

LABEL="local.claudemeter"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP="/Applications/ClaudeMeter.app"
DOMAIN="gui/$(id -u)"

case "${1:-status}" in
  install)
    if [[ ! -d "$APP" ]]; then
      echo "❌ 找不到 $APP，先跑 ./build.sh --install"
      exit 1
    fi
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>$APP</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <array>
        <string>Aqua</string>
    </array>
</dict>
</plist>
PLISTEOF
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "✅ 已启用开机自启动"
    ;;

  uninstall)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "✅ 已关闭开机自启动（launchd 任务和 plist 都已移除）"
    ;;

  status)
    if [[ -f "$PLIST" ]]; then
      echo "plist   : 存在  $PLIST"
    else
      echo "plist   : 不存在"
    fi
    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
      echo "launchd : 已加载"
      launchctl print "$DOMAIN/$LABEL" 2>/dev/null | grep -E "state =|pid =|program =" | head -3 | sed 's/^/          /'
    else
      echo "launchd : 未加载"
    fi
    ;;

  *)
    echo "用法: $0 install | uninstall | status"
    exit 1
    ;;
esac
