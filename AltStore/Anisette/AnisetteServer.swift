//
//  AnisetteServer.swift
//  AltStore
//
//  Created by Caroline Moore on 5/26/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation

struct AnisetteServer: Decodable
{
    var name: String
    var url: URL
}

struct AnisetteClientInfo: Decodable
{
    var clientInfo: String
    var userAgent: String

    // client_info is formatted as <device> <platform;version;build> <client>.
    private var components: [String] {
        clientInfo.split(separator: "<").compactMap { component in
            guard let end = component.firstIndex(of: ">") else { return nil }
            return String(component[..<end])
        }
    }

    var deviceType: String? { components.first }

    var operatingSystem: String? {
        guard components.count > 1 else { return nil }
        return components[1].split(separator: ";").first.map(String.init)
    }
}

extension AnisetteServer: Identifiable
{
    var id: URL { self.url }
}

private extension AnisetteServer
{
    var dictionaryRepresentation: [String: Any] {
        [
            CodingKeys.name.stringValue: self.name,
            CodingKeys.url.stringValue: self.url.absoluteString
        ]
    }

    init?(dictionary: [String: Any])
    {
        guard let name = dictionary[CodingKeys.name.stringValue] as? String,
              let urlString = dictionary[CodingKeys.url.stringValue] as? String,
              let url = URL(string: urlString)
        else { return nil }

        self.name = name
        self.url = url
    }
}

extension UserDefaults
{
    @nonobjc var anisetteServers: [AnisetteServer]? {
        get {
            guard let servers = _anisetteServers?.compactMap({ AnisetteServer(dictionary: $0) }) else { return nil }
            return servers
        }
        set {
            _anisetteServers = newValue?.map { $0.dictionaryRepresentation }
        }
    }
    @NSManaged @objc(anisetteServers) private var _anisetteServers: [[String: Any]]?
}
