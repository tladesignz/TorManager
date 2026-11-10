//
//  AppDelegate.swift
//  Example macOS
//
//  Created by Benjamin Erhart on 08.03.24.
//  Copyright © 2026 Guardian Project. All rights reserved.
//

import Cocoa
import TorManager_macOS
import IPtProxyUI_macOS
import IPtProxyUI_Shared

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Task {
            do {
                try await TorManager.shared.start(autoConf: !Settings.firstRunDone, smartConnect: true) { progress, summary in
                    print("progress=\(progress), summary=\(summary ?? "(nil)")")
                }
            }
            catch {
                print(error)
            }

            NotificationCenter.default.post(name: .init("tor-ready"), object: nil)

            Settings.firstRunDone = true

//            let config = URLSessionConfiguration.default
//            config.connectionProxyDictionary = TorManager.shared.torSocks5ProxyConf
//
//            let session = URLSession(configuration: config)
//
//            do {
//                let (data, response) = try await session.data(from: URL(string: "https://check.torproject.org")!)
//
//                print(response)
//
//                print(String(data: data, encoding: .utf8) ?? "(nil)")
//            }
//            catch {
//                print(error)
//            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    @IBAction
    func openSettings(_ sender: Any) {
        let vc = BridgesConfViewController()
        vc.countryCode = TorManager.shared.countryCode
        vc.transport = TorManager.shared.transport
        vc.customBridges = TorManager.shared.customBridges
        vc.delegate = TorManager.shared

        let window = NSWindow(contentViewController: vc)
        window.delegate = self
        window.styleMask.remove(.miniaturizable)

        NSApp.runModal(for: window)

        window.close()
    }


    // MARK: NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        NSApp.stopModal()
    }
}

extension TorManager {

   static let shared = TorManager(
    directory: FileManager.default.urls(
        for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("tor", isDirectory: true))
}

extension Settings {

    class var firstRunDone: Bool {
        get {
            defaults?.bool(forKey: "firstRunDone") ?? false
        }
        set {
            defaults?.set(newValue, forKey: "firstRunDone")
        }
    }
}
