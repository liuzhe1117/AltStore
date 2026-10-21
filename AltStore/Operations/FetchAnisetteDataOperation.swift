//
//  FetchAnisetteDataOperation.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CryptoKit
import Combine
import RegexBuilder

import AltStoreCore
import AltSign
import Roxas

private extension URL
{
    static let appleGSALookup = URL(string: "https://gsa.apple.com/grandslam/GsService2/lookup")!
}

extension FetchAnisetteDataOperation
{
    fileprivate struct AnisetteIdentity
    {
        let bytes: Data // 16 random bytes; stored as anisetteIdentityKey in keychain

        var identifier: String { bytes.base64EncodedString() }
        var localUserID: String { SHA256.hash(data: bytes).map { String(format: "%02X", $0) }.joined() }
        var deviceID: String { bytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }.uuidString }
        
        static func make() -> AnisetteIdentity
        {
            let new = AnisetteIdentity(bytes: Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }))
            return new
        }

        init(bytes: Data)
        {
            self.bytes = bytes
        }
    }
}

@objc(FetchAnisetteDataOperation)
class FetchAnisetteDataOperation: ResultOperation<ALTAnisetteData>, @unchecked Sendable
{
    let context: OperationContext

    private struct AuthenticationProvider
    {
        let url: URL
        let identityBytes: Data
        let adiPB: Data
        let clientInfo: String
        let userAgent: String
    }

    private enum AuthenticationRoute
    {
        case remote(AuthenticationProvider)
        case desktop(Server)
    }

    private struct AuthenticationBinding
    {
        let route: AuthenticationRoute
        let clientInfo: String
        let userAgent: String
        let deviceID: String
        let localUserID: String
    }

    private var lastRoute: AuthenticationRoute?
    private var lastUserAgent: String?
    private var authenticationBinding: AuthenticationBinding?
    
    private let session: URLSession
    
    init(context: OperationContext)
    {
        self.context = context
        
        let configuration = URLSessionConfiguration.default
        
        if UserDefaults.standard.responseCachingDisabled
        {
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
        }
        
        self.session = URLSession(configuration: configuration)
    }

    // Fetches fresh Anisette data using the route selected for this operation.
    // This is also used by AltSign after a two-factor challenge, when the
    // one-time password must be refreshed before the next GrandSlam request.
    func fetchAnisetteData() async throws -> ALTAnisetteData
    {
        let anisetteData: ALTAnisetteData
        if UserDefaults.shared.prefersRemoteAltServer
        {
            anisetteData = try await self.fetchAnisetteDataFromAvailableServer()
        }
        else if let server = self.context.server
        {
            anisetteData = try await self.fetchAnisetteData(fromAltServer: server)
            self.lastRoute = .desktop(server)
        }
        else
        {
            throw OperationError.serverNotFound
        }
        return self.normalizedAnisetteData(anisetteData)
    }

    // Called once after initial selection. Subsequent authentication steps use
    // this operation's immutable snapshot, never the current UI or keychain.
    func pinAuthenticationIdentity(_ anisetteData: ALTAnisetteData) throws
    {
        guard self.authenticationBinding == nil, let route = self.lastRoute else
        {
            throw self.authenticationIdentityChanged()
        }
        self.authenticationBinding = AuthenticationBinding(route: route,
            clientInfo: anisetteData.deviceDescription,
            userAgent: self.lastUserAgent ?? "akd/1.0 CFNetwork/808.1.4",
            deviceID: anisetteData.deviceUniqueIdentifier,
            localUserID: anisetteData.localUserID)
    }

    func fetchAuthenticationAnisetteData(resyncData: String? = nil) async throws -> ALTAnisetteData
    {
        guard let binding = self.authenticationBinding else { throw self.authenticationIdentityChanged() }
        let anisetteData: ALTAnisetteData
        switch binding.route
        {
        case .remote(let provider):
            anisetteData = try await self.fetchAnisetteData(from: provider.url, resyncData: resyncData, authenticationProvider: provider)
        case .desktop(let server):
            anisetteData = try await self.fetchAnisetteData(fromAltServer: server, resyncData: resyncData)
        }
        let normalized = self.normalizedAnisetteData(anisetteData)
        guard normalized.deviceDescription == binding.clientInfo,
              normalized.deviceUniqueIdentifier == binding.deviceID,
              normalized.localUserID == binding.localUserID,
              (self.lastUserAgent ?? "akd/1.0 CFNetwork/808.1.4") == binding.userAgent
        else { throw self.authenticationIdentityChanged() }
        return normalized
    }

    private func authenticationIdentityChanged() -> NSError
    {
        NSError(domain: "AltStore.AnisetteAuthenticationError", code: 1, userInfo: [
            NSLocalizedDescriptionKey: NSLocalizedString("The Anisette identity changed during authentication.", comment: ""),
            NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString("Start a new sign-in. This authentication attempt cannot switch Anisette servers or device identities.", comment: ""),
        ])
    }

    func resynchronizeAnisetteData(sim: String) async throws -> ALTAnisetteData
    {
        let anisetteData: ALTAnisetteData
        if UserDefaults.shared.prefersRemoteAltServer
        {
            anisetteData = try await self.fetchAnisetteDataFromAvailableServer(resyncData: sim)
        }
        else if let server = self.context.server
        {
            anisetteData = try await self.fetchAnisetteData(fromAltServer: server, resyncData: sim)
        }
        else
        {
            throw OperationError.serverNotFound
        }
        return self.normalizedAnisetteData(anisetteData)
    }

    private func normalizedAnisetteData(_ anisetteData: ALTAnisetteData) -> ALTAnisetteData
    {
        let regex = Regex {
            "com.apple.dt.Xcode/"
            OneOrMore {
                ChoiceOf {
                    .digit
                    "."
                }
            }
        }
        .ignoresCase()

        // Apply the same identity normalization to initial, refresh and resync
        // requests, including calls made after this Operation has finished.
        anisetteData.deviceDescription = anisetteData.deviceDescription.replacing(regex, with: "com.apple.akd/1.0")
        return anisetteData
    }
    
    override func main()
    {
        super.main()

        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }

        Task<Void, Never>
        {
            do
            {
                Logger.sideload.notice("Fetching anisette data...")

                let anisetteData = try await self.fetchAnisetteData()
                
                self.finish(.success(anisetteData))
            }
            catch
            {
                self.finish(.failure(error))
            }
        }
    }
}

private extension FetchAnisetteDataOperation
{
    func fetchAnisetteData(fromAltServer server: Server, resyncData: String? = nil) async throws -> ALTAnisetteData
    {
        return try await withCheckedThrowingContinuation { continuation in
            // Each fetch/refresh/resync owns a continuation, independently of
            // this Operation's lifetime. Consume it atomically before resuming:
            // connect, send and receive callbacks may fail concurrently.
            let continuationLock = NSLock()
            var pendingContinuation: CheckedContinuation<ALTAnisetteData, Error>? = continuation
            func finish(_ result: Result<ALTAnisetteData, Error>)
            {
                continuationLock.lock()
                let continuation = pendingContinuation
                pendingContinuation = nil
                continuationLock.unlock()
                continuation?.resume(with: result)
            }
            
            ServerManager.shared.connect(to: server) { (result) in
                switch result
                {
                case .failure(let error):
                    finish(.failure(error))
                case .success(let connection):
                    Logger.sideload.debug("Sending anisette data request...")

                    let request = AnisetteDataRequest(resyncData: resyncData)
                    connection.send(request) { (result) in
                        switch result
                        {
                        case .failure(let error):
                            Logger.sideload.error("Failed to send anisette data request. \(error.localizedDescription, privacy: .public)")
                            finish(.failure(error))

                        case .success:
                            Logger.sideload.debug("Waiting for anisette data...")
                            connection.receiveResponse() { (result) in
                                switch result
                                {
                                case .failure(let error):
                                    Logger.sideload.error("Failed to receive anisette data response. \(error.localizedDescription, privacy: .public)")
                                    finish(.failure(error))

                                case .success(.error(let response)):
                                    Logger.sideload.error("Failed to receive anisette data. \(response.error.localizedDescription, privacy: .public)")
                                    finish(.failure(response.error))

                                case .success(.anisetteData(let response)):
                                    Logger.sideload.notice("Successfully received anisette data!")
                                    self.lastUserAgent = response.userAgent
                                    ALTAppleAPI.shared.authenticationUserAgent = response.userAgent
                                    finish(.success(response.anisetteData))

                                case .success: finish(.failure(ALTServerError(.unknownResponse)))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    func fetchAnisetteDataFromAvailableServer(resyncData: String? = nil) async throws -> ALTAnisetteData
    {
        // Apple's resync challenge belongs to the already provisioned identity.
        // Never send it to a fallback provider or provision a new identity for it.
        if resyncData != nil
        {
            guard let storedURL = Keychain.shared.anisetteADIPBServerURL,
                  let serverURL = URL(string: storedURL)
            else { throw AnisetteServerError.invalidResponse(serverURL: nil, debugDescription: "No provisioned Anisette identity is available for resynchronization. Sign in again.") }
            return try await self.fetchAnisetteData(from: serverURL, resyncData: resyncData)
        }

        // Try the selected provider first, then the iLoader Mac providers and
        // PR #1835's Windows providers in that order.
        var attemptedURLs = Set<URL>()
        if let preferredURL = UserDefaults.shared.preferredAnisetteServerURL
        {
            attemptedURLs.insert(preferredURL)
            do
            {
                return try await self.fetchAnisetteData(from: preferredURL)
            }
            catch
            {
                if Task.isCancelled { throw CancellationError() }
                Logger.sideload.error("Preferred anisette server failed: \(error.localizedDescription, privacy: .public). Trying alternatives.")
            }
        }

        let servers: [AnisetteServer]
        do
        {
            servers = try await AnisetteServerManager.shared.fetchServers()
        }
        catch
        {
            Logger.sideload.error("Failed to fetch remote anisette server list: \(error.localizedDescription, privacy: .public)")
            if Task.isCancelled { throw CancellationError() }
            // A CDN outage must not prevent trying bundled or cached providers.
            servers = AnisetteServerManager.shared.cachedServers
        }

        // Randomize the remaining directory entries, keeping the preferred
        // iLoader providers first.
        for server in AnisetteServerManager.prioritizedServers(servers.shuffled())
        {
            guard attemptedURLs.insert(server.url).inserted else { continue }
            try Task.checkCancellation()
            do
            {
                let anisetteData = try await self.fetchAnisetteData(from: server.url, resyncData: resyncData)
                UserDefaults.shared.preferredAnisetteServerURL = server.url
                return anisetteData
            }
            catch
            {
                if Task.isCancelled { throw CancellationError() }
                Logger.sideload.error("Anisette server \(server.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public). Trying next.")
            }
        }

        Logger.sideload.error("All remote anisette servers failed.")
        throw AnisetteServerError.unavailable()
    }
    
    // Based on SideStore's FetchAnisetteDataOperation: https://github.com/SideStore/SideStore/blob/develop/AltStore/Operations/FetchAnisetteDataOperation.swift
    private func fetchAnisetteData(from serverURL: URL, resyncData: String? = nil, authenticationProvider: AuthenticationProvider? = nil) async throws -> ALTAnisetteData
    {
        // 1. Fetch client_info from the server
        let clientInfoURL = serverURL.appending(components: "v3", "client_info")
        
        let decoder = Foundation.JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let clientInfoRequest = URLRequest(url: clientInfoURL, cachePolicy: .reloadIgnoringLocalCacheData)
        let response: AnisetteClientInfo = try await self.send(clientInfoRequest, decoder: decoder, anisetteServerURL: serverURL)

        // A provider may change its backend at the same URL. Fail before
        // provisioning or sending the old identity to a different client.
        if let provider = authenticationProvider,
           provider.url != serverURL || provider.clientInfo != response.clientInfo || provider.userAgent != response.userAgent
        {
            throw self.authenticationIdentityChanged()
        }

        // Bind both the device identity and provisioning blob to the provider's
        // URL AND advertised identity. A backend can change at the same URL.
        let cachedIdentity = Keychain.shared.anisetteIdentityKey
        let cachedADIPB = Keychain.shared.anisetteADIPB
        let canReuseProvisioning = cachedIdentity?.count == 16 && cachedADIPB != nil &&
            Keychain.shared.anisetteADIPBServerURL == serverURL.absoluteString &&
            Keychain.shared.anisetteProvisioningClientInfo == response.clientInfo &&
            Keychain.shared.anisetteProvisioningUserAgent == response.userAgent

        guard authenticationProvider != nil || resyncData == nil || canReuseProvisioning else
        {
            throw AnisetteServerError.invalidResponse(serverURL: serverURL, debugDescription: "The Anisette provider identity changed. Sign in again before resynchronizing.")
        }

        // 2. Rotate the identifier whenever a new provisioning identity is needed.
        let identity: AnisetteIdentity
        if let provider = authenticationProvider
        {
            identity = AnisetteIdentity(bytes: provider.identityBytes)
        }
        else if canReuseProvisioning, let id = cachedIdentity
        {
            identity = AnisetteIdentity(bytes: id)
        }
        else
        {
            identity = AnisetteIdentity.make()
        }

        // 3. Provision against this server if we don't have a cached adi.pb
        let adiPB: Data
        if let provider = authenticationProvider
        {
            adiPB = provider.adiPB
        }
        else if canReuseProvisioning, let pb = cachedADIPB
        {
            adiPB = pb
        }
        else
        {
            Logger.sideload.notice("No cached adi.pb; running anisette provisioning against \(serverURL.absoluteString, privacy: .public).")
            adiPB = try await self.provision(against: serverURL, clientInfo: response.clientInfo, userAgent: response.userAgent, identity: identity)
            // Preserve the previous identity if provisioning fails. Write the
            // blob last so partially saved metadata is never considered valid.
            Keychain.shared.anisetteADIPB = nil
            Keychain.shared.anisetteIdentityKey = identity.bytes
            Keychain.shared.anisetteADIPBServerURL = serverURL.absoluteString
            Keychain.shared.anisetteProvisioningClientInfo = response.clientInfo
            Keychain.shared.anisetteProvisioningUserAgent = response.userAgent
            Keychain.shared.anisetteADIPB = adiPB
        }
        
        // 4. Fetch anisette headers
        let (machineID, oneTimePassword, routingInfo) = try await self.fetchHeaders(from: serverURL, identity: identity, adiPB: adiPB, resyncData: resyncData)

        // The User-Agent is part of the provider identity. AltSign uses it for
        // GrandSlam authentication, so do not discard it after provisioning.
        self.lastUserAgent = response.userAgent
        ALTAppleAPI.shared.authenticationUserAgent = response.userAgent
        self.lastRoute = .remote(AuthenticationProvider(url: serverURL, identityBytes: identity.bytes,
            adiPB: adiPB, clientInfo: response.clientInfo, userAgent: response.userAgent))

        // 5. Construct & return ALTAnisetteData
        return ALTAnisetteData(
            machineID: machineID,
            oneTimePassword: oneTimePassword,
            localUserID: identity.localUserID,
            routingInfo: routingInfo,
            deviceUniqueIdentifier: identity.deviceID,
            deviceSerialNumber: "C02LKHBBFD57",
            deviceDescription: response.clientInfo,
            date: .now,
            locale: .current,
            timeZone: .current
        )
    }

    func fetchHeaders(from serverURL: URL, identity: AnisetteIdentity, adiPB: Data, resyncData: String? = nil) async throws -> (machineID: String, oneTimePassword: String, routingInfo: UInt64)
    {
        let headersURL = serverURL.appending(components: "v3", "get_headers")

        var request = URLRequest(url: headersURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Body: Encodable
        {
            var identifier: String
            var adi_pb: String
            var sim: String?
            var device_id: String?
            var md_lu: String?
        }

        let body = Body(identifier: identity.identifier,
                        adi_pb: String(decoding: adiPB, as: UTF8.self),
                        sim: resyncData,
                        device_id: resyncData.map { _ in identity.deviceID },
                        md_lu: resyncData.map { _ in identity.localUserID })
        request.httpBody = try JSONEncoder().encode(body)

        struct Response: Decodable
        {
            var result: String?
            var message: String?
            var machineID: String?
            var oneTimePassword: String?
            var routingInfo: String?

            private enum CodingKeys: String, CodingKey
            {
                case result
                case message
                case machineID = "X-Apple-I-MD-M"
                case oneTimePassword = "X-Apple-I-MD"
                case routingInfo = "X-Apple-I-MD-RINFO"
            }
        }

        let response: Response = try await self.send(request, decoder: Foundation.JSONDecoder(), anisetteServerURL: serverURL)

        guard response.result != "GetHeadersError" else
        {
            Logger.sideload.error("Anisette headers request returned error: \(response.message ?? "(no message)", privacy: .public)")
            throw AnisetteServerError.invalidResponse(serverURL: serverURL, debugDescription: response.message)
        }

        guard let machineID = response.machineID,
              let oneTimePassword = response.oneTimePassword,
              let routingInfoString = response.routingInfo,
              let routingInfo = UInt64(routingInfoString)
        else
        {
            Logger.sideload.error("Anisette headers response was missing required fields.")
            throw AnisetteServerError.invalidResponse(serverURL: serverURL)
        }

        return (machineID, oneTimePassword, routingInfo)
    }

    // Based on SideStore's FetchAnisetteDataOperation: https://github.com/SideStore/SideStore/blob/develop/AltStore/Operations/FetchAnisetteDataOperation.swift
    func provision(against serverURL: URL, clientInfo: String, userAgent: String, identity: AnisetteIdentity) async throws -> Data
    {
        let jsonEncoder = JSONEncoder()
        let plistEncoder = PropertyListEncoder()
        plistEncoder.outputFormat = .xml

        // 1. Build Apple GSA lookup request
        let lookupRequest = self.makeAnisetteRequest(for: .appleGSALookup, clientInfo: clientInfo, userAgent: userAgent, identity: identity)

        // 2. Look up Apple's start/end provisioning URLs
        struct Response: Decodable
        {
            var urls: URLs

            struct URLs: Decodable
            {
                var midStartProvisioning: String
                var midFinishProvisioning: String
            }
        }

        let lookupResponse: Response = try await self.send(lookupRequest, decoder: PropertyListDecoder(), anisetteServerURL: nil)
        
        guard let startProvisioningURL = URL(string: lookupResponse.urls.midStartProvisioning),
              let endProvisioningURL = URL(string: lookupResponse.urls.midFinishProvisioning)
        else {
            Logger.sideload.error("Failed to construct provisioning URLs from server response.")
            throw OperationError.unknown(failureReason: "Couldn’t construct Apple GSA provisioning URL.")
        }
        
        // 3. Create and open WebSocket session to anisette server
        let provisioningSessionURL = serverURL.appending(components: "v3", "provisioning_session")

        var socketRequest = URLRequest(url: provisioningSessionURL)
        socketRequest.timeoutInterval = 30
        
        let socket = self.session.webSocketTask(with: socketRequest)
        socket.resume()
        
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        // 4. Drive provisioning state machine: respond to each server prompt until ProvisioningSuccess
        while true
        {
            let message = try await socket.receiveMessage()
            
            guard case .string(let text) = message, let data = text.data(using: .utf8) else {
                Logger.sideload.error("Received unexpected non-string message from anisette server.")
                throw AnisetteServerError.invalidResponse(serverURL: serverURL)
            }

            struct Message: Decodable
            {
                var result: String
                var message: String?
                var cpim: String?
                var adi_pb: String?
            }

            let response: Message = try Foundation.JSONDecoder().decode(Message.self, from: data)

            Logger.sideload.debug("Received provisioning response: \(response.result, privacy: .public)")
            
            switch response.result
            {
            case "GiveIdentifier":
                struct IDMessage: Encodable
                {
                    var identifier: String
                }
                
                let message = IDMessage(identifier: identity.identifier)
                let data = try jsonEncoder.encode(message)
                let string = String(decoding: data, as: UTF8.self)

                try await socket.send(.string(string))
                
            case "GiveStartProvisioningData":
                var startRequest = self.makeAnisetteRequest(for: startProvisioningURL, clientInfo: clientInfo, userAgent: userAgent, identity: identity)
                startRequest.httpMethod = "POST"
                
                struct Body: Encodable
                {
                    var Header: [String: String] = [:]
                    var Request: [String: String] = [:]
                }
                
                let body = Body()
                startRequest.httpBody = try plistEncoder.encode(body)

                struct StartMessage: Codable
                {
                    var spim: String
                }
                
                struct Response: Decodable
                {
                    var Response: StartMessage
                }

                let startResponse: Response = try await self.send(startRequest, decoder: PropertyListDecoder(), anisetteServerURL: nil)

                let message = StartMessage(spim: startResponse.Response.spim)
                let data = try jsonEncoder.encode(message)
                let string = String(decoding: data, as: UTF8.self)

                try await socket.send(.string(string))
                
            case "GiveEndProvisioningData":
                guard let cpim = response.cpim else {
                    Logger.sideload.error("GiveEndProvisioningData message didn't include cpim.")
                    throw AnisetteServerError.invalidResponse(serverURL: serverURL)
                }
                
                var endRequest = self.makeAnisetteRequest(for: endProvisioningURL, clientInfo: clientInfo, userAgent: userAgent, identity: identity)
                endRequest.httpMethod = "POST"
                
                struct Body: Encodable
                {
                    var Header: [String: String] = [:]
                    var Request: Request
                    
                    struct Request: Encodable
                    {
                        var cpim: String
                    }
                }
                
                let body = Body(Request: .init(cpim: cpim))
                endRequest.httpBody = try plistEncoder.encode(body)

                struct EndMessage: Codable
                {
                    var ptm: String
                    var tk: String
                }
                
                struct Response: Decodable
                {
                    var Response: EndMessage
                }

                let endResponse: Response = try await self.send(endRequest, decoder: PropertyListDecoder(), anisetteServerURL: nil)

                let message = EndMessage(ptm: endResponse.Response.ptm, tk: endResponse.Response.tk)
                let data = try jsonEncoder.encode(message)
                let string = String(decoding: data, as: UTF8.self)

                try await socket.send(.string(string))
                
            case "ProvisioningSuccess":
                guard let adiPB = response.adi_pb, let adiPBData = adiPB.data(using: .utf8) else {
                    Logger.sideload.error("ProvisioningSuccess message didn't include adi_pb.")
                    throw AnisetteServerError.invalidResponse(serverURL: serverURL)
                }
                                
                Logger.sideload.notice("Provisioning succeeded.")
                
                return adiPBData
                
            default:
                // Any unrecognized result is treated as fatal — we don't know what it means, so don't assume it's safe to ignore.
                Logger.sideload.error("Anisette server returned unrecognized result: \(response.result, privacy: .public) — \(response.message ?? "", privacy: .public)")
                throw AnisetteServerError.invalidResponse(serverURL: serverURL, debugDescription: response.message)
            }
        }
    }
}

private extension FetchAnisetteDataOperation
{
    func send<T: Decodable, Decoder: TopLevelDecoder>(_ request: URLRequest, decoder: Decoder, anisetteServerURL: URL?) async throws -> T where Decoder.Input == Data
    {
        let data: Data
        let urlResponse: URLResponse
        do
        {
            (data, urlResponse) = try await self.session.data(for: request)
        }
        catch
        {
            // We want to catch specific errors that indicate an issue with the anisette server, so
            // we can prompt users to try again or select a new server. All other errors fall through.
            let serverUnavailableErrorCodes: [URLError.Code] = [.cannotConnectToHost, .cannotFindHost, .timedOut, .badServerResponse]
            
            if anisetteServerURL != nil, let urlError = error as? URLError, serverUnavailableErrorCodes.contains(urlError.code)
            {
                throw AnisetteServerError.unavailable(serverURL: anisetteServerURL, underlyingError: urlError)
            }
            
            throw error
        }
        
        if let urlResponse = urlResponse as? HTTPURLResponse, urlResponse.statusCode != 200
        {
            Logger.sideload.error("Request to \(request.url?.absoluteString ?? "?", privacy: .public) failed with status \(urlResponse.statusCode).")
            
            if urlResponse.statusCode == 429 // TODO: create specific operation error case
            {
                throw OperationError.unknown(failureReason: String(localized: "Too many requests. Please wait a moment and try again.", comment: nil))
            }
            
            if anisetteServerURL != nil
            {
                throw AnisetteServerError.unavailable(serverURL: anisetteServerURL, debugDescription: String(localized: "The server returned HTTP error code \(urlResponse.statusCode)."))
            }
            
            throw OperationError.unknown(failureReason: String(localized: "The server returned HTTP error code \(urlResponse.statusCode).", comment: nil))
        }
        
        do
        {
            return try decoder.decode(T.self, from: data)
        }
        catch
        {
            if anisetteServerURL != nil
            {
                throw AnisetteServerError.invalidResponse(serverURL: anisetteServerURL, underlyingError: error)
            }

            throw error
        }
    }
    
    func makeAnisetteRequest(for url: URL, clientInfo: String, userAgent: String, identity: AnisetteIdentity) -> URLRequest
    {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/x-xml-plist", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(clientInfo, forHTTPHeaderField: "X-Mme-Client-Info")
        request.setValue(identity.localUserID, forHTTPHeaderField: "X-Apple-I-MD-LU")
        request.setValue(identity.deviceID, forHTTPHeaderField: "X-Mme-Device-Id")
        request.setValue(Locale.current.identifier, forHTTPHeaderField: "X-Apple-Locale")
        request.setValue(TimeZone.current.abbreviation(), forHTTPHeaderField: "X-Apple-I-TimeZone")
        request.setValue(ISO8601DateFormatter().string(from: .now), forHTTPHeaderField: "X-Apple-I-Client-Time")
        return request
    }
}

private extension URLSessionWebSocketTask
{
    func receiveMessage() async throws -> URLSessionWebSocketTask.Message
    {
        try await withCheckedThrowingContinuation { continuation in
            self.receive { result in
                continuation.resume(with: result)
            }
        }
    }
}
