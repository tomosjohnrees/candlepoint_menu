#!/bin/zsh
set -e
cd "${0:A:h}"

swift build -c release --product CandlepointMenu

bundle='Candlepoint Menu.app'
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
cp .build/release/CandlepointMenu "$bundle/Contents/MacOS/CandlepointMenu"
chmod +x "$bundle/Contents/MacOS/CandlepointMenu"
codesign --force --sign - --timestamp=none "$bundle"
echo "Built $bundle"
