//
//  AnisetteServerManager.swift
//  AltStore
//
//  Created by Caroline Moore on 6/19/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore

private extension URL
{
    static let anisetteServers = URL(string: "https://cdn.altstore.io/file/altstore/altstore/anisette-servers.json")!
}

class AnisetteServerManager
{
    static let shared = AnisetteServerManager()

    // Prefer the Mac providers currently used first by iLoader, then keep
    // PR #1835's Windows providers as fallbacks.
    static let preferredServers = [
        AnisetteServer(name: "SideStore (Mac ADI)", url: URL(string: "https://new.ani.sidestore.io")!),
        AnisetteServer(name: "jkcoxson (Mac ADI)", url: URL(string: "https://mac-ani.jkcoxson.com")!),
        AnisetteServer(name: "jkcoxson (Windows ADI)", url: URL(string: "https://ani.jkcoxson.com")!),
        AnisetteServer(name: "StikStore (Windows ADI)", url: URL(string: "https://ani2.stikstore.app")!),
    ]

    static func prioritizedServers(_ servers: [AnisetteServer]) -> [AnisetteServer]
    {
        var seen = Set<URL>()
        return (preferredServers + servers).filter { seen.insert($0.url).inserted }
    }

    var cachedServers: [AnisetteServer] {
        Self.prioritizedServers(UserDefaults.shared.anisetteServers ?? [])
    }

    private let session: URLSession

    private init()
    {
        let configuration = URLSessionConfiguration.default

        if UserDefaults.standard.responseCachingDisabled
        {
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
        }

        self.session = URLSession(configuration: configuration)
    }

    func fetchServers() async throws -> [AnisetteServer]
    {
        struct Response: Decodable
        {
            var servers: [AnisetteServer]
        }

        let (data, _) = try await self.session.data(from: .anisetteServers)
        let response = try Foundation.JSONDecoder().decode(Response.self, from: data)

        let servers = Self.prioritizedServers(response.servers)
        UserDefaults.shared.anisetteServers = servers

        return servers
    }

    // Verifies a URL points to a working anisette server.
    @discardableResult
    func validate(_ url: URL) async throws -> AnisetteClientInfo
    {
        let clientInfoURL = url.appending(components: "v3", "client_info")

        var request = URLRequest(url: clientInfoURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 30

        let (data, urlResponse) = try await self.session.data(for: request)

        if let urlResponse = urlResponse as? HTTPURLResponse
        {
            // URL points at something that isn't an anisette server.
            if urlResponse.statusCode == 404
            {
                throw AnisetteServerError.invalidServer()
            }

            // Server is reachable but erroring (e.g. 502/522 when its backend is down).
            guard urlResponse.statusCode == 200 else
            {
                Logger.sideload.error("Anisette server \(clientInfoURL, privacy: .public) returned status \(urlResponse.statusCode).")
                throw AnisetteServerError.unavailable(serverURL: url, debugDescription: String(localized: "The server returned HTTP error code \(urlResponse.statusCode)."))
            }
        }

        let decoder = Foundation.JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do
        {
            return try decoder.decode(AnisetteClientInfo.self, from: data)
        }
        catch
        {
            // Responded with 200, but the body isn't valid anisette client_info.
            throw AnisetteServerError.invalidServer()
        }
    }
}
