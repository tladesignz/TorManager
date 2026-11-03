//
//  TorManagerBase.swift
//  TorManager
//
//  Created by Benjamin Erhart on 8.03.24.
//  Copyright © 2024 Guardian Project. All rights reserved.
//

import Foundation
import Network
import os
import CTor


open class TorManagerBase {

    public static let torName = "Tor"


    private static let osLogger = Logger(subsystem: Bundle.main.bundleIdentifier!,
                                         category: String(describing: TorManagerBase.self))


    public let directory: URL
    public let geoipFile: URL?
    public let geoip6File: URL?

    /**
     Connected, if:

     - the `TorThread` is executing,
     - the Tor lock file exists,
     - the `TorController` is connected to Tor's control port.
     */
    public var connected: Bool {
        (torThread?.isExecuting ?? false)
        && (torConf?.isLocked ?? false)
        && (torController?.isConnected ?? false)
    }

    /**
     SOCKS5 endpoint of the started Tor to use with ``WKWebViewConfiguration.websiteDataStore.proxyConfigurations``.
     */
    public var torSocks5Endpoint: NWEndpoint? {
        guard connected, let port = torSocks5Port else {
            return nil
        }

        let host: IPv4Address

        if let hostString = torSocks5Host, let hostAddr = IPv4Address(hostString) {
            host = hostAddr
        }
        else {
            host = .loopback
        }

        return .hostPort(host: .ipv4(host), port: port)
    }

    /**
     SOCKS5 proxy configuration of the started Tor to use with ``URLSessionConfiguration.connectionProxyDictionary``.
     */
    public var torSocks5ProxyConf: [AnyHashable: Any]? {
        guard connected, let port = torSocks5Port?.rawValue else {
            return nil
        }

        return [
            kCFProxyTypeKey: kCFProxyTypeSOCKS,
            kCFStreamPropertySOCKSVersion: kCFStreamSocketSOCKSVersion5,
            kCFStreamPropertySOCKSProxyHost: torSocks5Host ?? "127.0.0.1",
            kCFStreamPropertySOCKSProxyPort: port]
    }

    /**
     SOCKS5 host of the started Tor. (Should be "127.0.0.1")
     */
    public private(set) var torSocks5Host: String? = nil

    /**
     SOCKS5 port of the started Tor.
     */
    public private(set) var torSocks5Port: NWEndpoint.Port? = nil

    /**
     The `TorThread` in which Tor is running.

     Read access is provided for informational purposes, only.

     Don't try to `cancel` Tor with this, it won't work.
     Tor needs to be stopped via the control port.

     Use ``TorManager.stop()`` instead, it will properly clean up everything.
     */
    public private(set) var torThread: TorThread?

    /**
     The `TorConfiguration` which was used to start Tor.
     */
    public private(set) var torConf: TorConfiguration?

    /**
     The `TorController` instance currently in use.
     */
    public private(set) var torController: TorController?


    private var smartGuard: DispatchSourceTimer?
    private var smartTimeout = DispatchTime.now()

    private var progressObs: Any?
    private var establishedObs: Any?


    public init(directory: URL, geoipFile: URL? = nil, geoip6File: URL? = nil) {
        self.directory = directory
        self.geoipFile = geoipFile
        self.geoip6File = geoip6File

        try? FileManager.default.createSecureDirIfNotExists(at: directory)
    }


    // MARK: Public Methods

    /**
     Start Tor, if it isn't, yet.

     If Tor is already running, will just reconfigure the bridge configuration.
     So, in case your user changed the bridge configuration, you can call this, too, but you can also call ``TorManager.reconfigureBridges()``.

     Will check for Orbot. If Orbot is running, and you provided an API token (see ``TorManager.evaluateOrbot()``),
     will configure Tor to bypass Orbot via its bypass port.

     - note: Please add the following to your `Info.plist` file for Orbot support to work:
     ```
     <key>LSApplicationQueriesSchemes</key>
     <array>
         <string>orbot</string>
     </array>
     ```

     If Orbot is running and no bypass port information can be aquired, will refrain from starting our own Tor.
     (Tor over Tor doesn't work...)

     - parameter autoConf: If set, will try auto-configuration using the Moat/RdSys service on every start.
        (ATTENTION: This will leak every Tor start to Tor Project. Not to censors necessarily, though, as that call will try to bypass censorship using Domain Fronting.)
     - parameter smartConnect: Automatically tries a cascade of Pluggable Transports, if no progress for 30 seconds, each.
     - parameter progressCallback: Will be called, in case Tor needs to start up and will be informed about that progress.
     - parameter progress: Value between 0 and 100.
     - throws: Reason, why Tor could not be started/no Tor SOCKS5 endpoint could be established.
     */
    open func start(autoConf: Bool = false, smartConnect: Bool = false,
                    _ progressCallback: ((_ progress: Int) -> Void)? = nil) async throws
    {
        let orbot = await evaluateOrbot()

        if orbot.running && orbot.bypassPort == nil {
            throw Errors.orbotRunningNoBypass
        }

        // If Tor is already running, just reconfigure bridges.
        if connected {
            try await reconfigureBridges()

            return
        }

        torSocks5Host = nil
        torSocks5Port = nil

        if autoConf {
            await doAutoConf(smartConnect)
        }

        do {
            try startTransport()

            // Create fresh - transport ports may have changed.
            self.torConf = self.createTorConf(orbot.bypassPort)
//            self.log(self.torConf!.compile().debugDescription)

            self.torThread?.cancel()
            self.torThread = TorThread(configuration: self.torConf)
            self.torThread?.start()

            try await Task.sleep(nanoseconds: UInt64(0.65 * Double(NSEC_PER_SEC)))

            if self.torController == nil, let cpf = self.torConf?.controlPortFile {
                self.torController = TorController(controlPortFile: cpf)
            }

            if !(self.torController?.isConnected ?? false) {
                try self.torController?.connect()
            }

            guard let cookie = self.torConf?.cookie else {
                throw Errors.cookieUnreadable
            }

            try await self.torController?.authenticate(with: cookie)

            var smartConnectFailed = false

            if smartConnect {
                self.connectionAlive()

                self.startSmartGuard {
                    smartConnectFailed = true
                }
            }

            if smartConnect || progressCallback != nil {
                var oldProgress = -1

                self.progressObs = self.torController?.addObserver(forStatusEvents: {
                    (type, severity, action, arguments) -> Bool in

                    guard type == "STATUS_CLIENT" && action == "BOOTSTRAP" else {
                        return false
                    }

                    let progress = Int(arguments?["PROGRESS"] ?? "0") ?? 0

                    if progress > oldProgress {
                        self.connectionAlive()
                        oldProgress = progress
                    }

                    progressCallback?(progress)

                    if progress >= 100 {
                        self.torController?.removeObserver(self.progressObs)
                    }

                    return true
                })
            }

            let _: Bool = try await withCheckedThrowingContinuation { continuation in
                self.establishedObs = self.torController?.addObserver(forCircuitEstablished: { established in
                    if smartConnectFailed {
                        return continuation.resume(throwing: Errors.smartConnectFailed)
                    }

                    guard established else {
                        return
                    }

                    continuation.resume(returning: true)
                })
            }

            self.stopSmartGuard()
            self.torController?.removeObserver(self.establishedObs)
            self.torController?.removeObserver(self.progressObs)

            let response = await self.torController?.info(forKeys: ["net/listeners/socks"])

            guard let parts = response?.first?.split(separator: ":"),
                  let host = parts.first,
                  let port = parts.last,
                  let port = NWEndpoint.Port(String(port))
            else {
                throw Errors.noSocksAddr
            }

            self.torSocks5Host = String(host)
            self.torSocks5Port = port
        }
        catch {
            self.stopSmartGuard()
            self.stop()

            throw error
        }
    }

    /**
     Stops Tor and any used Pluggable Transport.
     */
    open func stop() {
        torSocks5Host = nil
        torSocks5Port = nil

        torController?.removeObserver(establishedObs)
        torController?.removeObserver(progressObs)

        stopTransport()

        torController?.disconnect()
        torController = nil

        torThread?.cancel()
        torThread = nil

        torConf = nil
    }

    open func reconfigureBridges() async throws {
        fatalError("reconfigureBridges() must be implemented in a child class!")
    }

    /**
     Get a list of all currently available circuits with detailed information about their nodes.

     - note: There's no clear way to determine, which circuit actually was used by a specific request.

     - returns: A list of `TORCircuit`s . Empty if no circuit could be found or if ``TorManager.connected`` is `false`.
     */
    open func getCircuits() async -> [TorCircuit] {
        guard connected, let torController else {
            return []
        }

        return await torController.circuits()
    }

    /**
     Try to close a list of given circuits.

     The given circuits are invalid afterwards, as you just closed them. You should throw them away on completion.

     - parameter circuits: List of circuits to close.
     - returns: `true`, if *all* closings were successful, `false`, if *at least one* closing failed or if ``TorManager.connected`` is `false`.
    */
    open func close(_ circuits: [TorCircuit]) async -> Bool {
        guard connected, let torController else {
            return false
        }

        return await torController.close(circuits)
    }

    /**
     Checks, if Orbot is running and if it provides a bypass port.

     Will work with and without a negotiated API token.
     (But without, will not be able to get the bypass port information.)

     Provide the API token via `OrbotKit`:

     ```
     OrbotKit.shared.apiToken = "foobar"
     ```

     Read OrbotKit's documentation on how to acquire an API token.

     - note: This method does nothing on macOS. `OrbotKit` only supports iOS, since Orbot macOS doesn't have any API at the moment.

     - returns: Tuple with `running` flag indicating if Orbot is running, and `bypassPort`, indicating the port on localhost to bypass Orbot.
     */
    open func evaluateOrbot() async -> (running: Bool, bypassPort: UInt16?) {
        return (false, nil)
    }

    open func createTorConf(_ bypassPort: UInt16?) -> TorConfiguration {
        let conf = TorConfiguration()
        conf.ignoreMissingTorrc = true
        conf.cookieAuthentication = true
        conf.autoControlPort = true
        conf.avoidDiskWrites = true
        conf.geoipFile = geoipFile
        conf.geoip6File = geoip6File
        conf.dataDirectory = directory

        let authDir = directory.appendingPathComponent("auth", isDirectory: true)
        try? FileManager.default.createSecureDirIfNotExists(at: authDir)
        conf.clientAuthDirectory = authDir

        var options = ["LogMessageDomains": "1",
                       "SafeLogging": "1",
                       "SocksPort": "auto"]

#if DEBUG
        options["Log"] = "notice stdout"
#else
        options["Log"] = "err file /dev/null"
#endif

        if let port = bypassPort {
            options["Socks5Proxy"] = "127.0.0.1:\(port)"
        }

        conf.options.addEntries(from: options)

        return conf
    }

    open func doAutoConf(_ smartConnect: Bool) async {
        fatalError("doAutoConf() needs to be implemented in a child class.")
    }

    open func smartConnect(_ giveUp: @escaping () -> Void) async {
        fatalError("smartConnect() needs to be implemented in a child class.")
    }

    open func startTransport() throws {
        fatalError("startTransport() needs to be implemented in a child class.")
    }

    open func stopTransport() {
        fatalError("stopTransport() needs to be implemented in a child class.")
    }

    /**
     Start the smart guard.

     You should not call this directly. ``TorManager.start()`` will invoke this when necessary.

     This is declared open, so you can modify it.

     - parameter giveUp: Called, when smart connect couldn't find any working connection
     */
    open func startSmartGuard(giveUp: @escaping () -> Void) {
        // Create a new smart guard.
        smartGuard = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        smartGuard?.schedule(deadline: .now() + 1, repeating: .seconds(1))

        // If Tor's progress doesn't move within 30 seconds, try (another) bridge.
        smartGuard?.setEventHandler {
            guard DispatchTime.now() > self.smartTimeout else {
                return
            }

            self.connectionAlive()

            Task {
                await self.smartConnect(giveUp)
            }
        }

        smartGuard?.resume()
    }

    /**
     Give connection guard another 30 seconds to assume everything's ok.

     You should not call this directly. ``TorManager.start()`` will invoke this when necessary.

     This is declared open, so you can modify it.
     */
    open func connectionAlive() {
        smartTimeout = .now() + 30
    }

    /**
     Stop the smart guard.

     You should not call this directly. ``TorManager.start()`` will invoke this when necessary.

     This is declared open, so you can modify it.
     */
    open func stopSmartGuard() {
        smartGuard?.cancel()
        smartGuard = nil
    }

    public func log(_ message: String) {
        Self.osLogger.log(level: .debug, "\(message, privacy: .public)")
    }
}
