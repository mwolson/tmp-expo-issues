# ExpoModulesJSI keeps a slice that another Xcode built

Observed with expo 58.0.7 and expo-modules-jsi 58.0.10 on macOS 27.0.1, with
Xcode 27.0 (27A266a) and Xcode 27.1 (27A9275) installed side by side. Both
Xcodes report the same compiler,
`Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)`.

This is a blank `create-expo-app --template blank@sdk-58` app plus `repro.sh`.

`build-xcframework.sh` skips rebuilding an `ExpoModulesJSI.xcframework` slice
when its `.build-hash` matches. The hash covers the sources, `PODS_ROOT`,
`RN_ROOT` and `xcrun swiftc --version`, but not the Xcode build or its SDK.
After building with Xcode 27.0, a build with Xcode 27.1 reports the slice up to
date and keeps the one built against the iOS 27.0 SDK. Swift cannot use that
binary module with the 27.1 SDK, so every module that imports ExpoModulesJSI
recompiles it from its `.swiftinterface`. With 58.0.10 that fallback succeeds.
With expo-modules-jsi 58.0.7, in an app that also uses expo-sqlite, it failed in
ExpoSQLite with "requires the unavailable conformance of Bool to
JavaScriptRepresentable" (fixed for that case in 58.0.10 by
[#51234](https://github.com/expo/expo/pull/51234)), and
[#50365](https://github.com/expo/expo/issues/50365) hit "cannot find type
'__ObjC::expo' in scope" the same way.

Running `build-xcframework.sh` by hand with `DEVELOPER_DIR` set (instead of from
Xcode's build phase) has a second problem. The nested `xcodebuild` runs under
`env -i`, which keeps `PATH` but drops `DEVELOPER_DIR`, so it builds with the
Xcode chosen by `xcode-select`. Nothing in the hash notices, so the mismatched
slice looks up to date afterwards. Inside Xcode's build phase this does not
happen, because Xcode puts the building Xcode's tools first on `PATH`.

## Run

```bash
npm ci
OLD_XCODE=/Applications/Xcode.app NEW_XCODE=/Applications/Xcode-beta.app ./repro.sh
```

`OLD_XCODE` and `NEW_XCODE` must report the same `swiftc --version` and ship
different iOS SDKs. Each step is a Debug simulator build with its own derived
data; logs land in `logs/`.

## Result

```text
1-old-xcode (Xcode.app): BUILD SUCCEEDED; JSI slice rebuilt; ExpoModulesJSI compiled from .swiftinterface 0 times
2-new-xcode (Xcode-beta.app): BUILD SUCCEEDED; JSI slice reused; ExpoModulesJSI compiled from .swiftinterface 6 times
3-manual-build: build-xcframework.sh with DEVELOPER_DIR=Xcode-beta.app succeeded
3-new-xcode-after-manual-build (Xcode-beta.app): BUILD SUCCEEDED; JSI slice reused; ExpoModulesJSI compiled from .swiftinterface 6 times
```

With the fix proposed upstream (add the Xcode build to the hash and forward
`DEVELOPER_DIR` to the nested build) applied to
`node_modules/expo-modules-jsi/apple/scripts/build-xcframework.sh`:

```text
1-old-xcode (Xcode.app): BUILD SUCCEEDED; JSI slice rebuilt; ExpoModulesJSI compiled from .swiftinterface 0 times
2-new-xcode (Xcode-beta.app): BUILD SUCCEEDED; JSI slice rebuilt; ExpoModulesJSI compiled from .swiftinterface 0 times
3-manual-build: build-xcframework.sh with DEVELOPER_DIR=Xcode-beta.app succeeded
3-new-xcode-after-manual-build (Xcode-beta.app): BUILD SUCCEEDED; JSI slice reused; ExpoModulesJSI compiled from .swiftinterface 0 times
```

`npx expo-doctor@latest` passes all 20 checks on this app.
