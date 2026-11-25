//
//  Keychain.swift
//  AltServer
//
//  Created by Riley Testut on 10/20/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import Foundation
import KeychainAccess

@propertyWrapper
struct KeychainItem<Value>
{
    let key: String
    
    var wrappedValue: Value? {
        get {
            let keychain = Keychain.shared.keychain
            switch Value.self
            {
            case is Data.Type: return try? keychain.getData(self.key) as? Value
            case is String.Type: return try? keychain.getString(self.key) as? Value
            default: return nil
            }
        }
        set {
            let keychain = Keychain.shared.keychain
            switch Value.self
            {
            case is Data.Type: keychain[data: self.key] = newValue as? Data
            case is String.Type: keychain[self.key] = newValue as? String
            default: break
            }
        }
    }
    
    init(key: String)
    {
        self.key = key
    }
}

class Keychain
{
    static let shared = Keychain()
    
    fileprivate let keychain = KeychainAccess.Keychain(service: "com.rileytestut.AltServer").accessibility(.afterFirstUnlock).synchronizable(false)
    
    @KeychainItem(key: "anisetteIdentityKey")
    var anisetteIdentityKey: Data?
    
    @KeychainItem(key: "anisetteADIPB")
    var anisetteADIPB: Data?
    
    @KeychainItem(key: "anisetteProvisioningClientInfo")
    var anisetteProvisioningClientInfo: String?
    
    @KeychainItem(key: "anisetteProvisioningServerURL")
    var anisetteProvisioningServerURL: String?

    @KeychainItem(key: "anisetteProvisioningUserAgent")
    var anisetteProvisioningUserAgent: String?

    private init()
    {
    }
    
    func resetAnisetteIdentity()
    {
        self.anisetteIdentityKey = nil
        self.anisetteADIPB = nil
        self.anisetteProvisioningClientInfo = nil
        self.anisetteProvisioningServerURL = nil
        self.anisetteProvisioningUserAgent = nil
    }
}
