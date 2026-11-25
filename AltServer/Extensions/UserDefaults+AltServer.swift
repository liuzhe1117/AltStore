//
//  UserDefaults+AltServer.swift
//  AltServer
//
//  Created by Riley Testut on 7/31/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

extension UserDefaults
{
    var serverID: String? {
        get {
            return self.string(forKey: "serverID")
        }
        set {
            self.set(newValue, forKey: "serverID")
        }
    }
    
    var anisetteID: String? {
        get {
            return self.string(forKey: "anisetteID")
        }
        set {
            self.set(newValue, forKey: "anisetteID")
        }
    }
    
    var preferredAnisetteServerURL: URL? {
        get {
            return self.string(forKey: "preferredAnisetteServerURL").flatMap { URL(string: $0) }
        }
        set {
            self.set(newValue?.absoluteString, forKey: "preferredAnisetteServerURL")
        }
    }

    var didPresentInitialNotification: Bool {
        get {
            return self.bool(forKey: "didPresentInitialNotification")
        }
        set {
            self.set(newValue, forKey: "didPresentInitialNotification")
        }
    }
    
    func registerDefaults()
    {
        if self.serverID == nil
        {
            self.serverID = UUID().uuidString
        }
    }
}

// "Public" defaults configurable via CLI.
extension UserDefaults
{
    private static let altJITTimeoutKey = "JITTimeout"
    private static let anisetteServerURLKey = "RemoteAltServerURL"
    
    var altJITTimeout: TimeInterval? {
        let timeout = self.double(forKey: UserDefaults.altJITTimeoutKey) // Coerces strings into doubles.
        guard timeout != 0 else { return nil }
        
        return timeout
    }
    
    var anisetteServerURLOverride: URL? {
        return self.string(forKey: UserDefaults.anisetteServerURLKey).flatMap { URL(string: $0) }
    }
}
