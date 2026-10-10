# Expo issue repros

Minimal repros for Expo issues found while building
[T3 Code](https://github.com/pingdotgg/t3code)'s mobile app.

## Open

- [`jsi-xcframework-xcode-switch`](jsi-xcframework-xcode-switch) (observed with
  expo-modules-jsi 58.0.10, Xcode 27.0 and 27.1): `build-xcframework.sh` keys
  its slice cache on `swiftc --version` only, so switching to an Xcode with the
  same Swift compiler but a newer SDK reuses the old slice, and Swift recompiles
  ExpoModulesJSI from its `.swiftinterface` in every importing module. A manual
  run with `DEVELOPER_DIR` also builds with `xcode-select`'s Xcode, because the
  nested `xcodebuild` runs under `env -i`. Earlier report:
  [#50365](https://github.com/expo/expo/issues/50365)

  Upstream issue:
  [#51372 xcframework-xcode-switch](https://github.com/expo/expo/issues/51372)

  Upstream fix:
  [#51371 jsi-xcframework-xcode-switch](https://github.com/expo/expo/pull/51371)
