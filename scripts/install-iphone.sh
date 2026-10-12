#!/bin/bash
set -euo pipefail
umask 077
native_root="$(cd "$(dirname "$0")/.." && pwd)"
device_udid='00008150-00180C3A0A40401C'
bundle_id='com.wanderlog.travel'
proof_root="$(mktemp -d /tmp/wanderlog-native-install.XXXXXX)"
derived_root="$native_root/build-device-$(date +%Y%m%d-%H%M%S)"
printf '安装证据与本地记录备份：%s\n' "$proof_root"
xcrun devicectl list devices --json-output "$proof_root/devices.json" > "$proof_root/devices.log"
python3 "$native_root/scripts/device-proof.py" device "$proof_root/devices.json"
swift test --package-path "$native_root" --scratch-path "$proof_root/swift-build" > "$proof_root/tests.log" 2>&1
xcodebuild -quiet -project "$native_root/Wanderlog.xcodeproj" -scheme Wanderlog \
  -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$derived_root" \
  DEVELOPMENT_TEAM=UD4B2Y45PP build > "$proof_root/build.log" 2>&1
native_app="$derived_root/Build/Products/Release-iphoneos/Wanderlog.app"
codesign --verify --deep --strict "$native_app"
codesign -d --entitlements :- "$native_app" > "$proof_root/entitlements.plist" 2> "$proof_root/signature.log"
python3 - "$native_app/Info.plist" "$proof_root/entitlements.plist" <<'PY'
import plistlib, sys
info = plistlib.load(open(sys.argv[1], 'rb'))
rights = plistlib.load(open(sys.argv[2], 'rb'))
assert info['CFBundleIdentifier'] == 'com.wanderlog.travel'
assert rights['application-identifier'] == 'UD4B2Y45PP.com.wanderlog.travel'
assert rights['com.apple.developer.team-identifier'] == 'UD4B2Y45PP'
PY
# Copy only journey metadata, never private photo contents, before replacing the app.
xcrun devicectl device info files --device "$device_udid" --domain-type appDataContainer \
  --domain-identifier "$bundle_id" --json-output "$proof_root/files-before.json" > "$proof_root/files-before.log"
python3 "$native_root/scripts/device-proof.py" storage-files "$proof_root/files-before.json" > "$proof_root/storage-paths.txt"
while IFS= read -r storage_path; do
  mkdir -p "$proof_root/records/$(dirname "$storage_path")"
  xcrun devicectl device copy from --device "$device_udid" --domain-type appDataContainer \
    --domain-identifier "$bundle_id" --source "$storage_path" --destination "$proof_root/records/$storage_path" \
    > "$proof_root/backup.log" 2>&1
done < "$proof_root/storage-paths.txt"
xcrun devicectl device install app --device "$device_udid" "$native_app" \
  --json-output "$proof_root/install.json" > "$proof_root/install.log"
xcrun devicectl device info apps --device "$device_udid" --bundle-id "$bundle_id" \
  --json-output "$proof_root/apps-after.json" > "$proof_root/apps-after.log"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$native_app/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$native_app/Info.plist")
python3 "$native_root/scripts/device-proof.py" version "$proof_root/apps-after.json" "$version" "$build"
xcrun devicectl device info files --device "$device_udid" --domain-type appDataContainer \
  --domain-identifier "$bundle_id" --json-output "$proof_root/files-after.json" > "$proof_root/files-after.log"
python3 "$native_root/scripts/device-proof.py" photos "$proof_root/files-before.json" "$proof_root/files-after.json"
if xcrun devicectl device process launch --device "$device_udid" "$bundle_id" \
  --json-output "$proof_root/launch.json" > "$proof_root/launch.log" 2>&1; then
  printf '设备工具确认启动成功；实际界面与旧数据导入仍需核对。\n'
else
  printf '覆盖安装和版本已确认，启动未成功；请查看 %s/launch.log。\n' "$proof_root"
fi
