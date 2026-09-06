#!/bin/bash
set -euo pipefail

configuration="${1:-debug}"
bundle_id="${2:-com.taoofmac.stageprompter}"
identity_selector="${CODE_SIGN_IDENTITY:-}"
binary="$(swift build --disable-sandbox --show-bin-path --configuration "$configuration")/SmartPrompter"
app="build/Smart Prompter.app"

if [[ -z "$identity_selector" ]]; then
  identity_selector="$(
    security find-identity -v -p codesigning \
      | sed -n 's/^[[:space:]]*[0-9][0-9]*) \([0-9A-F][0-9A-F]*\) "Apple Development:.*"/\1/p' \
      | head -n 1
  )"
fi

if [[ -z "$identity_selector" ]]; then
  echo "error: no Apple Development code-signing identity is available" >&2
  echo "Create one through Xcode, or set CODE_SIGN_IDENTITY to another valid identity." >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "$identity_selector"; then
  echo "error: code-signing identity '$identity_selector' is unavailable" >&2
  echo "Set CODE_SIGN_IDENTITY to an identity listed by 'security find-identity -v -p codesigning'." >&2
  exit 1
fi

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/SmartPrompter"
cp docs/icon.png "$app/Contents/Resources/AppIcon.png"
sed "s/__BUNDLE_ID__/$bundle_id/g" Resources/Info.plist > "$app/Contents/Info.plist"
codesign \
  --force \
  --sign "$identity_selector" \
  --identifier "$bundle_id" \
  --entitlements Config/StagePrompter.entitlements \
  "$app"
echo "Built $app"
