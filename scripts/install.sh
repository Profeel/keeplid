#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

"${SCRIPT_DIR}/build.sh"

BIN_DIR="${ROOT_DIR}/.build/release"
TARGET_BIN_DIR="${HOME}/.local/bin"

echo "==> Installing CLI to ${TARGET_BIN_DIR}/keeplid..."
mkdir -p "${TARGET_BIN_DIR}"
cp -f "${BIN_DIR}/keeplid" "${TARGET_BIN_DIR}/keeplid"
chmod +x "${TARGET_BIN_DIR}/keeplid"

echo "==> Installing Standalone App to /Applications/KeepLid.app and ~/Applications/KeepLid.app..."
mkdir -p "${HOME}/Applications"

if [ -w "/Applications" ]; then
    rm -rf "/Applications/KeepLid.app"
    cp -R "${ROOT_DIR}/KeepLid.app" "/Applications/KeepLid.app"
    echo "    ✓ Installed to /Applications/KeepLid.app"
fi

rm -rf "${HOME}/Applications/KeepLid.app"
cp -R "${ROOT_DIR}/KeepLid.app" "${HOME}/Applications/KeepLid.app"
echo "    ✓ Installed to ~/Applications/KeepLid.app"

echo "==> Preparing ~/.keeplid..."
mkdir -p "${HOME}/.keeplid"

echo ""
echo "🎉 KeepLid (独立的 Mac App) 安装成功！"
echo ""
echo "1. 菜单栏独立 App:"
echo "   - 在聚焦搜索 (Spotlight) 或启动台 (Launchpad) 直接打开 'KeepLid'"
echo "   - 或终端执行: open /Applications/KeepLid.app"
echo ""
echo "2. 终端 CLI 工具:"
echo "   keeplid start 2h     # 合盖保活 2 小时"
echo "   keeplid start        # 无限期合盖保活"
echo "   keeplid stop         # 停止保活，恢复原生休眠策略"
echo "   keeplid status       # 查看实时状态与 Wi-Fi 延迟"
echo "   keeplid test-wifi    # 运行 10 秒 Wi-Fi 保活诊断"
echo ""
