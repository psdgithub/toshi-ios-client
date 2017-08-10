// Copyright (c) 2017 Token Browser, Inc
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import Foundation
import EtherealCereal
import HDWallet

/// An EtherealCereal wrapper. Generates the address and public key for a given private key. Signs messages.
public class Cereal: NSObject {

    static var shared: Cereal = Cereal()

    let entropyByteCount = 16

    var idCereal: EtherealCereal

    var walletCereal: EtherealCereal

    var mnemonic: BTCMnemonic

    static let privateKeyStorageKey = "cerealPrivateKey"

    public var address: String {
        return idCereal.address
    }

    public var paymentAddress: String {
        return walletCereal.address
    }

    // restore from words
    public init?(words: [String]) {
        guard let mnemonic = BTCMnemonic(words: words, password: nil, wordListType: .english) else { return nil }
        self.mnemonic = mnemonic

        Yap.sharedInstance.insert(object: self.mnemonic.words.joined(separator: " "), for: Cereal.privateKeyStorageKey)

        // ID path 0H/1/0
        let idKeychain = self.mnemonic.keychain.derivedKeychain(at: 0, hardened: true).derivedKeychain(at: 1).derivedKeychain(at: 0)
        let idPrivateKey = idKeychain.key.privateKey.hexadecimalString()
        idCereal = EtherealCereal(privateKey: idPrivateKey)

        // wallet path: 44H/60H/0H/0
        let walletKeychain = self.mnemonic.keychain.derivedKeychain(at: 44, hardened: true).derivedKeychain(at: 60, hardened: true).derivedKeychain(at: 0, hardened: true).derivedKeychain(at: 0).derivedKeychain(at: 0)
        let walletPrivateKey = walletKeychain.key.privateKey.hexadecimalString()
        walletCereal = EtherealCereal(privateKey: walletPrivateKey)

        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(userCreated(_:)), name: .userCreated, object: nil)
    }

    // restore from local user or create new
    public override init() {
        if let words = Yap.sharedInstance.retrieveObject(for: Cereal.privateKeyStorageKey) as? String {
            mnemonic = BTCMnemonic(words: words.components(separatedBy: " "), password: nil, wordListType: .english)!
        } else {
            var entropy = Data(count: entropyByteCount)
            // This creates the private key inside a block, result is of internal type ResultType.
            // We just need to check if it's 0 to ensure that there were no errors.
            let result = entropy.withUnsafeMutableBytes { mutableBytes in
                SecRandomCopyBytes(kSecRandomDefault, entropy.count, mutableBytes)
            }
            guard result == 0 else { fatalError("Failed to randomly generate and copy bytes for entropy generation. SecRandomCopyBytes error code: (\(result)).") }

            mnemonic = BTCMnemonic(entropy: entropy, password: nil, wordListType: .english)!
        }

        // ID path 0H/1/0
        let idKeychain = mnemonic.keychain.derivedKeychain(at: 0, hardened: true).derivedKeychain(at: 1).derivedKeychain(at: 0)
        let idPrivateKey = idKeychain.key.privateKey.hexadecimalString()
        idCereal = EtherealCereal(privateKey: idPrivateKey)

        // wallet path: 44H/60H/0H/0 and then 0 again. Metamask root path, first key.
        // Metamask allows multiple addresses, by incrementing the last path. So second key would be: 44H/60H/0H/0/1 and so on.
        let walletKeychain = mnemonic.keychain.derivedKeychain(at: 44, hardened: true).derivedKeychain(at: 60, hardened: true).derivedKeychain(at: 0, hardened: true).derivedKeychain(at: 0).derivedKeychain(at: 0)
        let walletPrivateKey = walletKeychain.key.privateKey.hexadecimalString()
        walletCereal = EtherealCereal(privateKey: walletPrivateKey)

        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(userCreated(_:)), name: .userCreated, object: nil)
    }

    // MARK: - Sign with id

    public func signWithID(message: String) -> String {
        return idCereal.sign(message: message)
    }

    public func signWithID(hex: String) -> String {
        return idCereal.sign(hex: hex)
    }

    public func sha3WithID(string: String) -> String {
        return idCereal.sha3(string: string)
    }

    public func sha3WithID(data: Data) -> String {
        return idCereal.sha3(data: data)
    }

    // MARK: - Sign with wallet

    public func signWithWallet(message: String) -> String {
        return walletCereal.sign(message: message)
    }

    public func signWithWallet(hex: String) -> String {
        return walletCereal.sign(hex: hex)
    }

    public func sha3WithWallet(string: String) -> String {
        return walletCereal.sha3(string: string)
    }
    
    @objc fileprivate func userCreated(_ notification: Notification) {
        Yap.sharedInstance.insert(object: mnemonic.words.joined(separator: " "), for: Cereal.privateKeyStorageKey)
    }
}
