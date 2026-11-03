//
//  TorManager.swift
//  TorManager
//
//  Created by Benjamin Erhart on 8.03.24.
//  Copyright © 2024 Guardian Project. All rights reserved.
//

import Foundation
import Tor
import IPtProxyUI
import Network
import os

#if os(iOS)
import OrbotKit
#endif

open class TorManager: BridgesConfDelegate {

    public static let torName = "Tor"


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


    private static let osLogger = Logger(subsystem: Bundle.main.bundleIdentifier!,
                                         category: String(describing: TorManager.self))


    public let directory: URL

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

    /**
     The current status of the IP stack.

     Some mobile providers turned to using IPv6 only.

     `TorManager` automatically will configure Tor properly, when this changes.
     */
    public private(set) var ipStatus = IpSupport.Status.unavailable


    private var smartGuard: DispatchSourceTimer?
    private var smartTimeout = DispatchTime.now()

    private var progressObs: Any?
    private var establishedObs: Any?


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
    public init(directory: URL) {
        self.directory = directory

        let ptDir = directory.appendingPathComponent("pt_state", isDirectory: true)
        try? createSecureDirIfNotExists(at: ptDir)
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
                    log(error.localizedDescription)
                }

                await torController?.resetConnection()
            }
        }
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

        do {
            try self.transport.start()

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

        transport.stop()

        torController?.disconnect()
        torController = nil

        torThread?.cancel()
        torThread = nil

        torConf = nil
    }


    /**
     Will reconfigure Tor with the updated bridge configuration, if it is already running.

     ATTENTION: If Tor is currently starting up, nothing will change.
     */
    open func reconfigureBridges() async throws {
        guard connected, let torController else {
            return // Nothing can be done. Will get configured on (next) start.
        }

        for key in ["UseBridges", "ClientTransportPlugin", "Bridge"] {
            do {
                try await torController.resetConf(forKey: key)
            }
            catch {
                log(error.localizedDescription)
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
        var running = false
        var bypassPort: UInt16? = nil

#if os(iOS)
        guard OrbotKit.shared.installed else {
            return (running, bypassPort)
        }

        let info: OrbotKit.Info?

        do {
            info = try await withCheckedThrowingContinuation { continuation in
                OrbotKit.shared.info { info, error in
                    if let error {
                        return continuation.resume(throwing: error)
                    }

                    continuation.resume(returning: info)
                }
            }

            switch info?.status {
            case .starting, .started:
                running = true

            default:
                // This happens, when Orbot is stopped, because
                // OrbotKit will synthesize an answer in that case.
                running = false
            }

            bypassPort = info?.bypassPort
        }
        catch {
            // We don't necessarily bother with an API token.
            // If something is installed which registered the `orbot` scheme
            // and something listens on the correct port, speaks HTTP and
            // answers with 403, than we have enough evidence, that
            // Orbot is running.
            if case OrbotKit.Errors.httpError(statusCode: 403) = error {
                running = true
            }
        }
#endif

        return (running, bypassPort)
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
    open func createTorConf(_ bypassPort: UInt16?) -> TorConfiguration {
        let conf = TorConfiguration()
        conf.ignoreMissingTorrc = true
        conf.cookieAuthentication = true
        conf.autoControlPort = true
        conf.avoidDiskWrites = true
        conf.geoipFile = Bundle.geoIp?.geoipFile
        conf.geoip6File = Bundle.geoIp?.geoip6File
        conf.dataDirectory = directory

        let authDir = directory.appendingPathComponent("auth", isDirectory: true)
        try? createSecureDirIfNotExists(at: authDir)
        conf.clientAuthDirectory = authDir

        var arguments = [String]()
        arguments += transport.torConf(Transport.asArguments).joined()
        arguments += ipStatus.torConf(transport, Transport.asArguments).joined()
        conf.arguments.addObjects(from: arguments)

        var options = ["LogMessageDomains": "1",
                       "SafeLogging": "1",
                       "SocksPort": "auto",
                       "UseBridges": transport == .none ? "0" : "1"]

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



    // MARK: BridgesConfDelegate

    public var countryCode: String? {
        get {
            Settings.countryCode
        }
        set {
            Settings.countryCode = newValue
        }
    }

    public var transport: IPtProxyUI.Transport {
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


    // MARK: Private Methods


    private func log(_ message: String) {
        Self.osLogger.log(level: .debug, "\(message, privacy: .public)")
    }

    private func createSecureDirIfNotExists(at url: URL) throws {
        // Try toemove it, if it is *not* a directory.
        if url.exists && !url.isDirectory {
            try FileManager.default.removeItem(at: url)
        }

        if !url.exists {
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        }
    }
}
