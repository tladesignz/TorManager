//
//  TorManager.swift
//  TorManager
//
//  Created by Benjamin Erhart on 3.11.26.
//  Copyright © 2026 Guardian Project. All rights reserved.
//

import Foundation
import TorManager_Shared
import IPtProxyUI_macOS
import CTor


open class TorManager: TorManagerBase, BridgesConfDelegate {

    /**
     The current status of the IP stack.

     Some mobile providers turned to using IPv6 only.

     `TorManager` automatically will configure Tor properly, when this changes.
     */
    public private(set) var ipStatus = IpSupport.Status.unavailable


    /**
     Initialize the `TorManager` class.

     You should encapsulate this in a singelton instantiator:

     ```
     extension TorManager {

        static let shared = TorManager(
            directory: FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("tor", isDirectory: true))
    }
     ```

     - parameter directory: Working directory for Tor and Pluggable Transports.
     */
    public override init(directory: URL, geoipFile: URL? = nil, geoip6File: URL? = nil) {
        super.init(directory: directory, geoipFile: geoipFile, geoip6File: geoip6File)

        let ptDir = directory.appendingPathComponent("pt_state", isDirectory: true)
        try? FileManager.default.createSecureDirIfNotExists(at: ptDir)
        Settings.stateLocation = ptDir

        Task {
            ipStatus = await withCheckedContinuation { continuation in
                IpSupport.shared.start { status in
                    continuation.resume(returning: status)
                }
            }

            if connected {
                do {
                    try await torController?.setConfs(ipStatus.torConf(transport, Transport.asConf))
                }
                catch {
                    self.log(error.localizedDescription)
                }

                await torController?.resetConnection()
            }
        }
    }


    /**
     Will reconfigure Tor with the updated bridge configuration, if it is already running.

     ATTENTION: If Tor is currently starting up, nothing will change.
     */
    open override func reconfigureBridges() async throws {
        guard connected, let torController else {
            return // Nothing can be done. Will get configured on (next) start.
        }

        for key in ["UseBridges", "ClientTransportPlugin", "Bridge"] {
            do {
                try await torController.resetConf(forKey: key)
            }
            catch {
                self.log(error.localizedDescription)
            }
        }

        // First, stop all transports.
        transport.stopAllOthers()

        guard transport != .none else {
            return
        }

        // Then start the needed one, if not started, yet.
        try transport.start()

        var conf = transport.torConf(Transport.asConf)
        conf.append(Transport.asConf(key: "UseBridges", value: "1"))

//        log(conf.debugDescription)

        try await torController.setConfs(conf)
    }

    /**
     Creates the Tor configuration from the current circumstances.

     Circumstances are:
     - Currently selected Pluggable Transport, if any.
     - Currently detected IP stack configuration.
     - Orbot bypass port, if any.

     Calling this directly will just give you the Tor configuration as it would be generated now.
     You can inspect it (see ``TorConfiguration.compile()``) or read the lock or cookie file.

     This will be called from ``TorManager.start()`` and is mainly declared open,, so you can modify the configuration,
     in case you need anything changed. (E.g. logging, Tor services...)

     - parameter bypassPort: The port provided by Orbot to bypass its Tor.
     */
    open override func createTorConf(_ bypassPort: UInt16?) -> TorConfiguration {
        let conf = super.createTorConf(bypassPort)

        var arguments = [String]()
        arguments += transport.torConf(Transport.asArguments).joined()
        arguments += ipStatus.torConf(transport, Transport.asArguments).joined()
        conf.arguments.addObjects(from: arguments)

        conf.options.setValue(transport == .none ? "0" : "1", forKey: "UseBridges")

        return conf
    }

    open override func doAutoConf(_ smartConnect: Bool) async {
        do {
            try await AutoConf(self).do()
        }
        catch {
            self.log("auto-conf error=\(error)")

            // If the API is broken, we continue with our own smart connect logic,
            // if that is requested, else we leave this setting alone.
            if smartConnect {
                self.transport = .none
            }
        }
    }

    open override func smartConnect(_ giveUp: @escaping () -> Void) async {
        var working = false

        repeat {
            switch self.transport {

                // If direct connection didn't work, try Snowflake bridge.
            case .none:
                self.transport = .snowflake

                // If Snowflake didn't work, try custom or default Obfs4 bridges.
            case .snowflake, .snowflakeAmp:
                self.transport.stop()

                if !(self.customBridges?.isEmpty ?? true) {
                    self.transport = .custom
                }
                else {
                    self.transport = .obfs4
                }

                // If custom Obfs4 bridges didn't work, try default ones.
            case .custom:
                self.transport.stop()

                self.transport = .obfs4

                // If Obfs4 bridges didn't work, give up.
            default:
                return giveUp()
            }

            do {
                try await self.reconfigureBridges()
                working = true
            }
            catch {
                self.log(error.localizedDescription)
            }
        }
        while !working
    }

    open override func startTransport() throws {
        try transport.start()
    }

    open override func stopTransport() {
        transport.stop()
    }


    // MARK: BridgesConfDelegate

    public var countryCode: String? {
        get {
            Settings.countryCode
        }
        set {
            Settings.countryCode = newValue
        }
    }

    public var transport: IPtProxyUI_Shared.Transport {
        get {
            Settings.transport
        }
        set {
            Settings.transport = newValue
        }
    }

    public var customBridges: [String]? {
        get {
            Settings.customBridges
        }
        set {
            Settings.customBridges = newValue
        }
    }

    public func save() {
        // Nothing to do here.
    }
}
