//
//  Errors.swift
//  TorManager
//
//  Created by Benjamin Erhart on 03.11.26.
//  Copyright © 2026 Guardian Project. All rights reserved.
//

import Foundation

public enum Errors: LocalizedError {
    case orbotRunningNoBypass
    case cookieUnreadable
    case noSocksAddr
    case smartConnectFailed

    public var errorDescription: String? {
        switch self {
        case .orbotRunningNoBypass:
            return "Orbot is running, but no bypass port provided by Orbot."

        case .cookieUnreadable:
            return "Tor cookie unreadable."

        case .noSocksAddr:
            return "No Tor SOCKS port provided by Tor."

        case .smartConnectFailed:
            return "Smart Connect failed."
        }
    }
}
