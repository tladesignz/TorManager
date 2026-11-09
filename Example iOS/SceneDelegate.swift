//
//  SceneDelegate.swift
//  TorManager_Example
//
//  Created by Benjamin Erhart on 03.11.26.
//  Copyright © 2026 Guardian Project. All rights reserved.
//

import UIKit
import TorManager_iOS_UI
import TorManager_iOS

class SceneDelegate: UIResponder, UIWindowSceneDelegate, StartTorViewControllerDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else {
            return
        }

        window = UIWindow(frame: scene.coordinateSpace.bounds)
        window?.windowScene = scene
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        let vc = StartTorViewController()
        vc.torManager = TorManager.shared
        vc.delegate = self

        show(vc)
    }


    // MARK: StartTorViewControllerDelegate

    func started() {
        if let vc = UIStoryboard(name: "Main", bundle: .main).instantiateInitialViewController() {
            show(vc)
        }
    }


    // MARK: Private Methods

    private func show(_ vc: UIViewController) {
        window?.rootViewController = vc
        window?.makeKeyAndVisible()

        if let window {
            UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: nil)
        }
    }
}
