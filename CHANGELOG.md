# TorManager

## 1.1.0
- Updated dependencies.
- Hooked `TorManager.reconfigureBridges()` on `BridgesConfDelegate.save()` so it actually does the useful thing automatically.
- Added `summary` from C-Tor to `TorManager.start()`'s  progress callback.
- Improved examples.
- Added a `TorManager-iOS-UI` library with a localized `StartTorViewController` to show as a scene while starting Tor. Allows users to change bridges during startup.

## 1.0.0
- Updated dependencies.
- Changed API so it is fully async/await compatible.
- Last CocoaPods release.

## 0.5.0
- Updated dependencies.

## 0.4.0
- Updated dependencies.

## 0.3.2

- Updated dependencies.
- Fixed issues with Objective-C/Swift data type interoperability.

## 0.3.1

- Make sure to not advertise any SOCKS5 access, if Tor is not running.

## 0.3.0

- Fixed bug with smart connect.
- Made `TorManager.Errors` public.
- Added constant for the word "Tor".

## 0.2.0

- Improved logging.
- Improved observer destruction.
- Added `clientAuthDirectory` support.
- Added creation of Tor working directories with proper access rights.
