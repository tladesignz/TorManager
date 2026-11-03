//
//  AppDelegate.swift
//  TorManager
//
//  Created by Benjamin Erhart on 03/08/2024.
//  Copyright (c) 2024 Benjamin Erhart. All rights reserved.
//

import UIKit
import TorManager

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool 
    {
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

            let request = URLRequest(url: URL(string: "https://check.torproject.org")!)

            print(request)

            do {
                let (data, response) = try await session.data(from: URL(string: "https://check.torproject.org")!)

                print(response)

                print(String(data: data, encoding: .utf8) ?? "(nil)")
            }
            catch {
                print(error)
            }
        }

        return true
    }
}

extension TorManager {

   static let shared = TorManager(
    directory: FileManager.default.urls(
        for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("tor", isDirectory: true))
}
