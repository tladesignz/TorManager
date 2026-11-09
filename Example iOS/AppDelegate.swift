//
//  AppDelegate.swift
//  TorManager
//
//  Created by Benjamin Erhart on 03/08/2024.
//  Copyright © 2026 Guardian Project. All rights reserved.
//

import UIKit
import TorManager_iOS

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

}

extension TorManager {

   static let shared = TorManager(
    directory: FileManager.default.urls(
        for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("tor", isDirectory: true))
}
