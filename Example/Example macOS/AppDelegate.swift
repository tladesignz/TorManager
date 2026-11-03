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
        Task {
            do {
                try await TorManager.shared.start(autoConf: true, smartConnect: true) { progress in
                    print("progress=\(progress)")
                }
            }
            catch {
                print(error)
            }

            let config = URLSessionConfiguration.default
            config.connectionProxyDictionary = TorManager.shared.torSocks5ProxyConf

            let session = URLSession(configuration: config)

            do {
                let (data, response) = try await session.data(from: URL(string: "https://check.torproject.org")!)

                print(response)

                print(String(data: data, encoding: .utf8) ?? "(nil)")
            }
            catch {
                print(error)
            }
        }
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
