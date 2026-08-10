#!/bin/bash
# 生成「拖拽安装」风格 DMG：左侧 App 图标 → 箭头 → 右侧 Applications 文件夹。
# 打包方案：create-dmg 8.1.0（内部用 appdmg，自带 660x422 浅灰底+深灰箭头背景）。
# 自动 patch macos-alias：修复 APFS 挂载卷 getVolumeName() 返回空串、
# 导致 .DS_Store 中 backgroundImageAlias 卷名为空、Finder 背景不显示的问题。
# 用法：./make-dmg-dragdrop.sh [输出.dmg 路径]（默认 ~/Downloads/Moongate-macOS-v<版本>.dmg）
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="月之门"
VERSION="${MOONGATE_VERSION:-0.8.2}"
# MOONGATE_BUILD_NUMBER / SPARKLE_FEED_URL 等环境变量原样透传给 build.sh（build.sh 自带默认值）
OUT="${1:-$HOME/Downloads/Moongate-macOS-v$VERSION.dmg}"

BUILD_STAGING="$(mktemp -d /tmp/moongate-dragdrop-build-XXXXXX)"
trap 'rm -rf "$BUILD_STAGING"' EXIT

APP="$BUILD_STAGING/Applications/$APP_NAME.app"

# create-dmg 固定工作目录（含 package.json 与 node_modules）
DMG_TOOL_DIR="/Users/manfred/code/projects/Moon/tools/dmg"

# ---- 1. 构建 App（staging，不触碰本机 /Applications）----
echo "==> 构建 $APP_NAME 到 staging（$BUILD_STAGING/Applications）"
INSTALL_DIR="$BUILD_STAGING/Applications" "$PROJ_DIR/build.sh"

# ---- 2. 校验 build 产物 ----
if [[ ! -d "$APP" ]]; then
    echo "==> 错误：build 产物不存在：$APP" >&2
    exit 1
fi

# ---- 3. 检查 node / npm ----
echo "==> 检查 node / npm 环境"
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "==> 错误：create-dmg 需要 node 与 npm，请先安装 Node.js" >&2
    exit 1
fi

# ---- 4. 初始化 create-dmg 工作目录并安装依赖 ----
echo "==> 初始化 create-dmg 工作目录：$DMG_TOOL_DIR"
mkdir -p "$DMG_TOOL_DIR"
if [[ ! -f "$DMG_TOOL_DIR/package.json" ]]; then
    cat > "$DMG_TOOL_DIR/package.json" <<'JSON'
{
  "name": "moongate-dmg",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "create-dmg": "^8.1.0"
  }
}
JSON
fi
if [[ ! -d "$DMG_TOOL_DIR/node_modules" ]]; then
    echo "==> 安装 create-dmg 依赖（npm install）"
    (cd "$DMG_TOOL_DIR" && npm install --no-fund --no-audit)
fi

# ---- 5. patch macos-alias（幂等）：修复 APFS 挂载卷 getVolumeName 返回空串 ----
PATCH_FILE="$DMG_TOOL_DIR/node_modules/macos-alias/lib/create.js"
if grep -q '|| path.basename(volumePath)' "$PATCH_FILE"; then
    echo "==> macos-alias 已包含卷名修复（无需 patch）"
else
    echo "==> patch macos-alias：修复 APFS 卷名为空导致 Finder 背景不显示"
    perl -pi -e 's/name: addon\.getVolumeName\(volumePath\),/name: addon.getVolumeName(volumePath) || path.basename(volumePath),/' "$PATCH_FILE"
    if ! grep -q '|| path.basename(volumePath)' "$PATCH_FILE"; then
        echo "==> 错误：macos-alias patch 失败（未找到待替换代码）" >&2
        exit 1
    fi
fi

if [[ "${MOONGATE_DRY_RUN:-}" == "1" ]]; then
    echo "==> [dry-run] 停止于 create-dmg 之前（未生成 DMG）"
    exit 0
fi

# ---- 6. 确保卷名不冲突（避免 hdiutil 自动改名成「月之门 1」导致 alias 卷名不匹配）----
if [[ -d "/Volumes/$APP_NAME" ]]; then
    echo "==> 卸载已挂载的 /Volumes/${APP_NAME}（避免卷名冲突）"
    hdiutil detach "/Volumes/$APP_NAME" || diskutil eject "/Volumes/$APP_NAME"
fi

# ---- 7. 用 create-dmg 打包 ----
OUT_DIR="$(dirname "$OUT")"
mkdir -p "$OUT_DIR"
echo "==> 生成 DMG（create-dmg，卷名 ${APP_NAME}）"
"$DMG_TOOL_DIR/node_modules/.bin/create-dmg" --overwrite --no-code-sign --dmg-title="$APP_NAME" "$APP" "$OUT_DIR"

# ---- 8. 重命名为脚本原有命名（Moongate-macOS-v<版本>.dmg）----
DMG_CREATED="$OUT_DIR/$APP_NAME $VERSION.dmg"
if [[ -f "$DMG_CREATED" && "$DMG_CREATED" != "$OUT" ]]; then
    echo "==> 重命名为：$OUT"
    rm -f "$OUT"
    mv "$DMG_CREATED" "$OUT"
fi

echo "==> 完成：$OUT"
echo "    （分发到其他 Mac：首次打开需右键 → 打开，或先执行"
echo "      xattr -dr com.apple.quarantine \"/Applications/$APP_NAME.app\"）"
