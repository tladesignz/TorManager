//
//  AppDelegate.swift
//  Example macOS
//
//  Created by Benjamin Erhart on 08.03.24.
//  Copyright © 2024 CocoaPods. All rights reserved.
//

import Cocoa
import TorManager

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        TorManager.shared.start { error in
            print("[\(String(describing: type(of: self)))] error=\(error?.localizedDescription ?? "(nil)")")

            let config = URLSessionConfiguration.default
            config.connectionProxyDictionary = TorManager.shared.torSocks5ProxyConf

            let session = URLSession(configuration: config)

            let request = URLRequest(url: URL(string: "https://check.torproject.org")!)

            print(request)

            session.dataTask(with: request) { data, response, error in
                if let response = response {
                    print(response)
                }

                if let error = error {
                    print(error)
                }

                if let data = data {
                    print(String(data: data, encoding: .utf8) ?? "(nil)")
                }
            }.resume()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

extension TorManager {

   static let shared = TorManager(
    directory: FileManager.default.urls(
        for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("tor", isDirectory: true))
}
