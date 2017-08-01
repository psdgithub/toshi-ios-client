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
import SweetSwift
import KeychainSwift

public extension NSNotification.Name {
    public static let currentUserUpdated = NSNotification.Name(rawValue: "currentUserUpdated")
    public static let userCreated = NSNotification.Name(rawValue: "userCreated")
    public static let userLoggedIn = NSNotification.Name(rawValue: "userLoggedIn")
}

public typealias UserInfo = (address: String, paymentAddress: String?, avatarPath: String?, name: String?, username: String?, isLocal: Bool)

public class TokenUser: NSObject, NSCoding {

    struct Constants {
        static let name = "name"
        static let username = "username"
        static let address = "token_id"
        static let paymentAddress = "payment_address"
        static let location = "location"
        static let about = "about"
        static let avatar = "avatar"
        static let isApp = "is_app"
        static let verified = "verified"
        static let isPublic = "public"
        static let reputationScore = "reputation_score"
        static let averageRating = "average_rating"
    }

    static let viewExtensionName = "TokenContactsDatabaseViewExtensionName"
    static let favoritesCollectionKey: String = "TokenContacts"

    public static let storedUserKey = "StoredUser"

    public static let storedContactKey = "storedContactKey"

    var category = ""

    var balance = NSDecimalNumber.zero

    private(set) var verified: Bool = false {
        didSet {
            self.save()
        }
    }

    private(set) var name = ""

    var displayUsername: String {
        return "@\(username)"
    }
    private(set) var username = ""
    private(set) var about = ""
    private(set) var location = ""
    private(set) var avatarPath = ""

    private(set) var isPublic = false

    private(set) var address = ""
    private(set) var paymentAddress = ""
    private(set) var isApp: Bool = false
    private(set) var reputationScore: Float?
    private(set) var averageRating: Float?

    fileprivate static var _current: TokenUser?
    fileprivate(set) static var current: TokenUser? {
        get {
            if _current == nil {
                _current = retrieveCurrentUserFromStore()
            }

            return _current
        }
        set {
            guard _current != newValue else { return }

            newValue?.update()

            if let user = newValue {
                user.save()
            }

            _current = newValue
            NotificationCenter.default.post(name: .currentUserUpdated, object: nil)
        }
    }

    var isBlocked: Bool {
        let blockingManager = OWSBlockingManager.shared()

        return blockingManager.blockedPhoneNumbers().contains(address)
    }

    var isCurrentUser: Bool {
        return address == Cereal.shared.address
    }

    public var JSONData: Data {
        return try! JSONSerialization.data(withJSONObject: asDict, options: [])
    }

    var asDict: [String: Any] {
        return [
            Constants.address: self.address,
            Constants.paymentAddress: self.paymentAddress,
            Constants.username: self.username,
            Constants.about: self.about,
            Constants.location: self.location,
            Constants.name: self.name,
            Constants.avatar: self.avatarPath,
            Constants.isApp: self.isApp,
            Constants.verified: self.verified,
            Constants.isPublic: self.isPublic
        ]
    }

    var userInfo: UserInfo {
        return UserInfo(address: address, paymentAddress: paymentAddress, avatarPath: avatarPath, name: name, username: displayUsername, isLocal: true)
    }

    public override var description: String {
        return "<User: address: \(address), payment address: \(paymentAddress), name: \(name), username: \(username), avatarPath: \(avatarPath)>"
    }

    static func name(from username: String) -> String {
        return username.hasPrefix("@") ? username.substring(from: username.index(after: username.startIndex)) : username
    }

    static func user(with data: Data, shouldUpdate: Bool = true) -> TokenUser? {
        guard let deserialised = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard let json = deserialised as? [String: Any] else { return nil }

        return TokenUser(json: json, shouldSave: shouldUpdate)
    }

    public init(json: [String: Any], shouldSave: Bool = true) {
        super.init()

        update(json: json, updateAvatar: true, shouldSave: shouldSave)

        setupNotifications()
    }

    public required convenience init?(coder aDecoder: NSCoder) {
        guard let jsonData = aDecoder.decodeObject(forKey: "jsonData") as? Data else { return nil }
        guard let deserialised = try? JSONSerialization.jsonObject(with: jsonData, options: []), let json = deserialised as? [String: Any] else { return nil }

        self.init(json: json)
    }

    @objc(encodeWithCoder:) public func encode(with aCoder: NSCoder) {
        aCoder.encode(JSONData, forKey: "jsonData")
    }

    func updateVerificationState(_ verified: Bool) {
        self.verified = verified
    }

    func update(json: [String: Any], updateAvatar _: Bool = false, shouldSave: Bool = true) {
        isPublic = json[Constants.isPublic] as? Bool ?? isPublic
        address = json[Constants.address] as! String
        paymentAddress = (json[Constants.paymentAddress] as? String) ?? (json[Constants.address] as! String)
        username = json[Constants.username] as! String
        name = json[Constants.name] as? String ?? name
        location = json[Constants.location] as? String ?? location
        about = json[Constants.about] as? String ?? about
        avatarPath = json[Constants.avatar] as? String ?? avatarPath
        isApp = json[Constants.isApp] as? Bool ?? isApp
        verified = json[Constants.verified] as? Bool ?? verified
        reputationScore = json[Constants.reputationScore] as? Float ?? reputationScore
        averageRating = json[Constants.averageRating] as? Float ?? averageRating

        if shouldSave {
            save()
        }
    }

    func update(avatar _: UIImage, avatarPath: String) {
        self.avatarPath = avatarPath

        save()
    }

    func update(username: String? = nil, name: String? = nil, about: String? = nil, location: String? = nil) {
        self.username = username ?? self.username
        self.name = name ?? self.name
        self.about = about ?? self.about
        self.location = location ?? self.location

        save()
    }

    func updatePublicState(to isPublic: Bool) {
        self.isPublic = isPublic

        IDAPIClient.shared.updateUser(asDict) { _, _ in }

        save()
    }

    public static func createCurrentUser(with json: [String: Any]) {
        guard let newUser = TokenUser(json: json) as TokenUser? else { return }
        current = newUser
        Yap.sharedInstance.setupForNewUser(with: newUser.address)
        NotificationCenter.default.post(name: .userCreated, object: nil)
    }

    public static func createOrUpdateCurrentUser(with json: [String: Any]) {
        guard current != nil else {
            current = TokenUser(json: json)
            NotificationCenter.default.post(name: .userCreated, object: nil)
            
            return
        }

        current?.update(json: json)
    }

    public static func retrieveCurrentUser() {
        current = retrieveCurrentUserFromStore()

        NotificationCenter.default.post(name: .userCreated, object: nil)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(updateIfNeeded), name: IDAPIClient.didFetchContactInfoNotification, object: nil)
    }

    @objc private func updateIfNeeded(_ notification: Notification) {
        guard let tokenContact = notification.object as? TokenUser else { return }
        guard tokenContact.address == address else { return }

        if name == tokenContact.name && username == tokenContact.username && location == tokenContact.location && about == tokenContact.about {
            return
        }

        update(username: tokenContact.username, name: tokenContact.name, about: tokenContact.about, location: tokenContact.location)
    }

    private func save() {
        if isCurrentUser {
            Yap.sharedInstance.insert(object: JSONData, for: TokenUser.storedUserKey)
        } else {
            Yap.sharedInstance.insert(object: JSONData, for: address, in: TokenUser.storedContactKey)
        }
    }

    private static func retrieveCurrentUserFromStore() -> TokenUser? {
        var user: TokenUser?
        
        if _current == nil, let userData = (Yap.sharedInstance.retrieveObject(for: TokenUser.storedUserKey) as? Data),
            let deserialised = (try? JSONSerialization.jsonObject(with: userData, options: [])),
            var json = deserialised as? [String: Any] {

            // Because of payment address migration, we have to override the stored payment address.
            // Otherwise users will be sending payments to the wrong address.
            if json[Constants.paymentAddress] as? String != Cereal.shared.paymentAddress {
                json[Constants.paymentAddress] = Cereal.shared.paymentAddress
            }

            user = TokenUser(json: json)
        }

        return user
    }
}
