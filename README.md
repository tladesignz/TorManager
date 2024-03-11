# TorManager

[![Version](https://img.shields.io/cocoapods/v/TorManager.svg?style=flat)](https://cocoapods.org/pods/TorManager)
[![License](https://img.shields.io/cocoapods/l/TorManager.svg?style=flat)](https://cocoapods.org/pods/TorManager)
[![Platform](https://img.shields.io/cocoapods/p/TorManager.svg?style=flat)](https://cocoapods.org/pods/TorManager)

The easiest way to integrate Tor and Pluggable Transports into your app.

This library bundles all building blocks to integrate Tor into your app:
- Tor.framework using
  - C-Tor
  - GeoIP files
- IPtProxyUI using
  - Lyrebird Pluggable Transport
  - Snowflake Pluggable Transport
  - Auto-configuration support via Moat/RdSys services
  - Auto-configuration support for IPv4/IPv6 cappable networks
- OrbotKit to detect and interact with a running Orbot

Plus
- A "smart connect" algorithm to automatically step through the transports to
  find a connection in hostile environments.
- Provide correct `WKWebView` and `URLSession` proxy configurations.

For an easy, no-brainer integration, change your `AppDelegate` like this:

```swift

import TorManager

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        TorManager.shared.start { error in
            print("[\(String(describing: type(of: self)))] error=\(error?.localizedDescription ?? "(nil)")")
        }

        return true
    }
}

extension TorManager {

   static let shared = TorManager(
    directory: FileManager.default.urls(
        for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("tor", isDirectory: true))
}
```

Then, when you instantiate a `WKWebView`:

```swift
    let webViewConfiguration = WKWebViewConfiguration()
    
    if #available(iOS 17.0, *), let proxy = TorManager.shared.torSocks5Endpoint {
        webViewConfiguration.websiteDataStore.proxyConfigurations.removeAll()
        webViewConfiguration.websiteDataStore.proxyConfigurations.append(ProxyConfiguration(socksv5Proxy: proxy))
    }

    let webView = WKWebView(frame: .zero, configuration: webViewConfiguration)
```

To configure a `URLSession`:

```swift
    let config = URLSessionConfiguration.default
    config.connectionProxyDictionary = TorManager.shared.torSocks5ProxyConf

    let session = URLSession(configuration: config)
```



## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

C-Tor will be compiled on your machine, hence you need to have the necessary dependencies available:

```sh
brew install automake autoconf libtool gettext
```

For more details, see the [Tor.framework README](https://github.com/iCepa/Tor.framework/blob/pure_pod/README.md)


### iOS Orbot support

Please add the following to your `Info.plist` file for Orbot support to work:

 ```xml
 <key>LSApplicationQueriesSchemes</key>
 <array>
     <string>orbot</string>
 </array>
 ```

## Installation

TorManager is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'TorManager'
```

## Build

```sh
pod trunk push --allow-warnings
```

## Author

Benjamin Erhart, berhart@netzarchitekten.com
for the [Guardian Project](https://guardianproject.info)


## License

TorManager is available under the MIT license. See the LICENSE file for more info.
