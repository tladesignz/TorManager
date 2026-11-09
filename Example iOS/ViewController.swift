//
//  ViewController.swift
//  TorManager
//
//  Created by Benjamin Erhart on 03/08/2024.
//  Copyright © 2026 Guardian Project. All rights reserved.
//

import UIKit
import WebKit
import TorManager_iOS
import IPtProxyUI_iOS

class ViewController: UIViewController, WKNavigationDelegate {

    private var webView: WKWebView!


    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.leftBarButtonItem = .init(barButtonSystemItem: .compose, target: self, action: #selector(configureBridges))

        let conf = WKWebViewConfiguration()

        if #available(iOS 17.0, macOS 14.0, *), let endpoint = TorManager.shared.torSocks5Endpoint {
            conf.websiteDataStore.proxyConfigurations.removeAll()
            conf.websiteDataStore.proxyConfigurations.append(ProxyConfiguration(socksv5Proxy: endpoint))
        }

        webView = WKWebView(frame: .zero, configuration: conf)
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)
        webView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        webView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        webView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        webView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true

        webView.navigationDelegate = self

        webView.load(.init(url: .init(string: "https://check.torproject.org")!))
    }


    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        var title = webView.title

        if title?.isEmpty ?? true {
            title = webView.url?.host
        }

        navigationItem.title = title
    }


    // MARK: Actions

    @IBAction
    open func configureBridges() {
        let vc = BridgesConfViewController()
        vc.delegate = TorManager.shared

        present(UINavigationController(rootViewController: vc), animated: true)
    }
}

