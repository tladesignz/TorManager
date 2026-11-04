//
//  StartTorViewController.swift
//  TorManager
//
//  Created by Benjamin Erhart on 03.11.26.
//  Copyright © 2026 Guardian Project. All rights reserved.
//

import UIKit
import IPtProxyUI_iOS
import TorManager_iOS

public protocol StartTorViewControllerDelegate: AnyObject {

    func started()
}

open class StartTorViewController: UIViewController {

    open weak var torManager: TorManager?

    open weak var delegate: StartTorViewControllerDelegate?


    @IBOutlet weak var titleLb: UILabel! {
        didSet {
            titleLb.text = NSLocalizedString("Starting Tor…", comment: "")
        }
    }

    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!

    @IBOutlet weak var retryBt: UIButton! {
        didSet {
            retryBt.setTitle(NSLocalizedString("Retry", comment: ""), for: .normal)
        }
    }

    @IBOutlet weak var progressView: UIProgressView!

    @IBOutlet weak var statusLb: UILabel!

    @IBOutlet weak var bridgesBt: UIButton! {
        didSet {
            bridgesBt.setTitle(NSLocalizedString("Configure Bridges", comment: ""), for: .normal)
        }
    }


    public init() {
        super.init(nibName: String(describing: type(of: self)), bundle: .module)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }


    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        retry()
    }


    // MARK: Actions

    @IBAction
    open func retry() {
        activityIndicator.isHidden = false
        retryBt.isHidden = true
        progressView.progress = 0
        statusLb.isHidden = true

        Task { [weak self] in
            do {
                try await self?.torManager?.start() { progress, summary in
                    Task { @MainActor in
                        self?.progressView.setProgress(Float(progress) / 100, animated: true)

                        UIAccessibility.post(notification: .announcement, argument: String(format: "%d%%", progress))

                        if let summary = summary, !summary.isEmpty {
                            self?.statusLb.text = summary
                            self?.statusLb.textColor = .label
                            self?.statusLb.isHidden = false
                        }
                        else {
                            self?.statusLb.isHidden = true
                        }
                    }
                }
            }
            catch {
                self?.activityIndicator.isHidden = true
                self?.retryBt.isHidden = false
                self?.statusLb.text = error.localizedDescription
                self?.statusLb.textColor = .systemRed
                self?.statusLb.isHidden = false

                UIAccessibility.post(notification: .announcement, argument: self?.statusLb.text)

                return
            }

            self?.delegate?.started()
        }
    }

    @IBAction
    open func configureBridges() {
        let vc = BridgesConfViewController()
        vc.delegate = torManager

        present(UINavigationController(rootViewController: vc), animated: true)
    }
}
