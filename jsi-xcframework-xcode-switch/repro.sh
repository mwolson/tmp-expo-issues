#!/usr/bin/env bash
# Reproduce expo-modules-jsi reusing an ExpoModulesJSI.xcframework slice that
# another Xcode built, when both Xcodes report the same `swiftc --version`.
#
# Needs two Xcodes with the same Swift compiler and different iOS SDKs, for
# example Xcode 27.0 (selected with xcode-select) and Xcode 27.1:
#
#   npm ci
#   OLD_XCODE=/Applications/Xcode.app NEW_XCODE=/Applications/Xcode-beta.app ./repro.sh
#
# Steps, each a Debug simulator build of this blank SDK 58 app:
#   1. Build with OLD_XCODE. The JSI build phase builds the slice.
#   2. Build with NEW_XCODE. Expected: the phase rebuilds the slice for this
#      Xcode. Actual: it reports the slice up to date, Swift cannot use the
#      binary module, and it recompiles ExpoModulesJSI from its .swiftinterface.
#   3. Run build-xcframework.sh by hand with DEVELOPER_DIR=NEW_XCODE, then build
#      with NEW_XCODE. Expected: the slice matches NEW_XCODE. Actual: the nested
#      xcodebuild runs under `env -i` without DEVELOPER_DIR and uses
#      xcode-select's Xcode, so step 2 repeats.

set -uo pipefail

OLD_XCODE=${OLD_XCODE:-/Applications/Xcode.app}
NEW_XCODE=${NEW_XCODE:-/Applications/Xcode-beta.app}
NPX=${NPX:-npx}
# CocoaPods needs a UTF-8 locale, which SSH sessions often lack.
export LANG=${LANG:-en_US.UTF-8} LC_ALL=${LC_ALL:-en_US.UTF-8}
here=$(cd "$(dirname "$0")" && pwd)
logs="$here/logs"

cd "$here" || exit 1
[[ -d node_modules ]] || { echo "Run npm ci first."; exit 1; }
rm -rf "$logs" "$here/derived"
mkdir -p "$logs"

for xcode in "$OLD_XCODE" "$NEW_XCODE"; do
    echo "$(basename "$xcode"): $(DEVELOPER_DIR="$xcode/Contents/Developer" xcodebuild -version | sed -n 1p)," \
        "iOS Simulator SDK $(DEVELOPER_DIR="$xcode/Contents/Developer" xcrun --sdk iphonesimulator --show-sdk-version)," \
        "$(DEVELOPER_DIR="$xcode/Contents/Developer" xcrun swiftc --version 2>&1 | sed -n 1p)"
done
echo "xcode-select: $(xcode-select -p)"

if ! compgen -G 'ios/*.xcworkspace' > /dev/null; then
    DEVELOPER_DIR="$OLD_XCODE/Contents/Developer" CI=1 "$NPX" expo prebuild --clean --platform ios > "$logs/prebuild.log" 2>&1 \
        || { echo "prebuild failed; see $logs/prebuild.log"; exit 1; }
fi
echo "expo $(node -p 'require("expo/package.json").version'), expo-modules-jsi $(node -p 'require("expo-modules-jsi/package.json").version')"

jsi_dir=$(node -p 'require("path").dirname(require.resolve("expo-modules-jsi/package.json"))')
slice="$jsi_dir/apple/Products/ExpoModulesJSI.xcframework/ios-arm64_x86_64-simulator"
workspace=$(ls -d ios/*.xcworkspace | head -1)
scheme=$(basename "$workspace" .xcworkspace)

build() {
    local name=$1 xcode=$2 log="$logs/$1.log" result phase interface
    if DEVELOPER_DIR="$xcode/Contents/Developer" xcodebuild \
        -workspace "$workspace" -scheme "$scheme" -configuration Debug \
        -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$here/derived/$name" CODE_SIGNING_ALLOWED=NO build \
        > "$log" 2>&1; then
        result="BUILD SUCCEEDED"
    else
        result="BUILD FAILED"
    fi
    if grep -q 'xcframework slices up to date, skipping build' "$log"; then
        phase="JSI slice reused"
    elif grep -q 'Built xcframework successfully' "$log"; then
        phase="JSI slice rebuilt"
    else
        phase="JSI phase did not finish"
    fi
    interface=$(grep -c 'CompileModuleFromInterface.*ExpoModulesJSI' "$log")
    echo "$name ($(basename "$xcode")): $result; $phase; ExpoModulesJSI compiled from .swiftinterface $interface times"
    if [[ $result == "BUILD FAILED" ]]; then
        grep -m3 'error:' "$log" | cut -c1-240 | sed 's/^/    /'
    fi
}

# Start from a slice that only OLD_XCODE has built.
rm -f "$slice/.build-hash"
build 1-old-xcode "$OLD_XCODE"
build 2-new-xcode "$NEW_XCODE"

rm -f "$slice/.build-hash"
if DEVELOPER_DIR="$NEW_XCODE/Contents/Developer" PODS_ROOT="$PWD/ios/Pods" PLATFORM_NAME=iphonesimulator \
    "$jsi_dir/apple/scripts/build-xcframework.sh" > "$logs/3-manual-build.log" 2>&1; then
    echo "3-manual-build: build-xcframework.sh with DEVELOPER_DIR=$(basename "$NEW_XCODE") succeeded"
else
    echo "3-manual-build: build-xcframework.sh failed; see $logs/3-manual-build.log"
fi
build 3-new-xcode-after-manual-build "$NEW_XCODE"
