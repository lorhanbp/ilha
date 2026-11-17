#!/bin/zsh
set -e
cd "${0:A:h}"
swift build -c release
APP=build/Ilha.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Ilha "$APP/Contents/MacOS/Ilha"
clang -dynamiclib -fobjc-arc -framework Foundation native/adapter.m -o "$APP/Contents/Resources/libIlhaNP.dylib"
cp native/np.pl "$APP/Contents/Resources/np.pl"
cat > "$APP/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.ilha</string>
<key>CFBundleName</key><string>Ilha</string>
<key>CFBundleExecutable</key><string>Ilha</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
codesign --force --sign "Ilha Dev" "$APP" 2>/dev/null || codesign --force --sign - "$APP"
echo "ok: $APP"
if [[ "$1" == "--install" ]]; then
    pkill -x Ilha || true
    sleep 1
    rm -rf /Applications/Ilha.app
    cp -R "$APP" /Applications/Ilha.app
    open /Applications/Ilha.app
    echo "instalado: /Applications/Ilha.app"
fi
