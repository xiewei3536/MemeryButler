#!/bin/bash
# MemoryButler 一鍵建置:Universal Binary → .app → .dmg
set -euo pipefail
cd "$(dirname "$0")"

APP="MemoryButler"
DISPLAY_NAME="記憶體管家"
BUNDLE_ID="com.bowei.memorybutler"
DIST="dist"

# 版本號優先順序：環境變數 VERSION → 目前 commit 的 tag（CI 由 tag 觸發）→ 下方預設值。
# 一定要與 release tag 一致：App 內建更新是用這個數字和 GitHub 最新 tag 比較，
# 若打包出來的版本落後 tag，使用者會被「新版本可用」無限循環提示。
# 只有在工作樹乾淨時才採用 tag（有未提交的修改就不是那個 release 了）
TAG_VERSION=""
if git diff-index --quiet HEAD -- 2>/dev/null; then
    TAG_VERSION="$(git describe --tags --exact-match 2>/dev/null || true)"
fi
VERSION="${VERSION:-${TAG_VERSION}}"
VERSION="${VERSION#v}"
VERSION="${VERSION:-1.3.1}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
echo "▸ 版本 $VERSION (build $BUILD_NUMBER)"

echo "▸ 編譯 Universal Binary (x86_64 + arm64)…"
rm -rf "$DIST"
mkdir -p "$DIST"

if swift build -c release --arch x86_64 --arch arm64 2>/dev/null; then
    UNIVERSAL="$(swift build -c release --arch x86_64 --arch arm64 --show-bin-path)/$APP"
else
    echo "  （合併模式不支援，改用分別編譯 + lipo）"
    swift build -c release --triple x86_64-apple-macosx
    BIN_X86="$(swift build -c release --triple x86_64-apple-macosx --show-bin-path)/$APP"
    swift build -c release --triple arm64-apple-macosx
    BIN_ARM="$(swift build -c release --triple arm64-apple-macosx --show-bin-path)/$APP"
    UNIVERSAL="$DIST/$APP-universal"
    lipo -create "$BIN_X86" "$BIN_ARM" -output "$UNIVERSAL"
fi
lipo -info "$UNIVERSAL"

echo "▸ 產生圖示…"
ICONSET="$DIST/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/make_icon.swift "$DIST/icon_1024.png"
for SZ in 16 32 128 256 512; do
    sips -z $SZ $SZ "$DIST/icon_1024.png" --out "$ICONSET/icon_${SZ}x${SZ}.png" >/dev/null
    DBL=$((SZ * 2))
    sips -z $DBL $DBL "$DIST/icon_1024.png" --out "$ICONSET/icon_${SZ}x${SZ}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$DIST/AppIcon.icns"

echo "▸ 組裝 $APP.app…"
BUNDLE="$DIST/$APP.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$UNIVERSAL" "$BUNDLE/Contents/MacOS/$APP"
cp "$DIST/AppIcon.icns" "$BUNDLE/Contents/Resources/"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP</string>
    <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>為 8GB 小記憶體 Mac 而生。</string>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc 簽名…"
codesign --force --deep -s - "$BUNDLE"
codesign --verify --deep "$BUNDLE" && echo "  簽名驗證通過"

echo "▸ 製作 DMG…"
STAGE="$DIST/dmg-stage"
mkdir -p "$STAGE"
cp -R "$BUNDLE" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"
hdiutil create -volname "$APP" -srcfolder "$STAGE" -format UDZO -ov "$DIST/$APP.dmg" >/dev/null
rm -rf "$STAGE" "$ICONSET" "$DIST/icon_1024.png"

echo ""
echo "✅ 完成:"
echo "   $DIST/$APP.app   （可直接拖進「應用程式」）"
echo "   $DIST/$APP.dmg   （可分享給其他 Intel / Apple Silicon Mac）"
