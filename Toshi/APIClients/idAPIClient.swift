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

import UIKit
import AwesomeCache
import SweetFoundation
import Teapot

public class IDAPIClient: NSObject, CacheExpiryDefault {
    public static let shared: IDAPIClient = IDAPIClient()

    public static let usernameValidationPattern = "^[a-zA-Z][a-zA-Z0-9_]+$"

    public static let updateContactsNotification = Notification.Name(rawValue: "UpdateContactWithAddress")

    public static let didFetchContactInfoNotification = Notification.Name(rawValue: "DidFetchContactInfo")

    public static let allowedSearchTermCharacters = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: ":/?#[]@!$&'()*+,;= "))

    public var teapot: Teapot

    private var contactCache = try! Cache<TokenUser>(name: "tokenContactCache")

    let contactUpdateQueue = DispatchQueue(label: "token.updateContactsQueue")

    public var baseURL: URL

    private override init() {
        baseURL = URL(string: TokenIdServiceBaseURLPath)!
        teapot = Teapot(baseURL: baseURL)

        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(updateAllContacts), name: IDAPIClient.updateContactsNotification, object: nil)
    }

    /// We use a background queue and a semaphore to ensure we only update the UI
    /// once all the contacts have been processed.
    func updateAllContacts() {
        updateContacts(for: TokenUser.storedContactKey)
        updateContacts(for: TokenUser.favoritesCollectionKey)
    }

    private func updateContacts(for collectionKey: String) {
        contactUpdateQueue.async {
            guard let contactsData = Yap.sharedInstance.retrieveObjects(in: collectionKey) as? [Data] else { return }
            let semaphore = DispatchSemaphore(value: 0)

            for contactData in contactsData {
                guard let dictionary = try? JSONSerialization.jsonObject(with: contactData, options: []) else { continue }

                if let dictionary = dictionary as? [String: Any] {
                    let tokenContact = TokenUser(json: dictionary)
                    self.findContact(name: tokenContact.address) { updatedContact in
                        if let updatedContact = updatedContact {
                            DispatchQueue.main.async {
                                Yap.sharedInstance.insert(object: updatedContact.JSONData, for: updatedContact.address, in: collectionKey)
                            }
                        }

                        semaphore.signal()
                    }
                    // calls to `wait()` need to be balanced with calls to `signal()`
                    // remember to call it _after_ the code we need to run asynchronously.
                    _ = semaphore.wait(timeout: .distantFuture)
                }
            }
        }
    }

    func updateContact(with identifier: String) {
        findContact(name: identifier) { updatedContact in
            if let updatedContact = updatedContact {
                DispatchQueue.main.async {
                    Yap.sharedInstance.insert(object: updatedContact.JSONData, for: updatedContact.address, in: TokenUser.storedContactKey)

                    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
                    appDelegate.contactsManager.refreshContacts()
                }
            }
        }
    }

    func fetchTimestamp(_ completion: @escaping ((Int) -> Void)) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.teapot.get("/v1/timestamp") { (result: NetworkResult) in
                switch result {
                case .success(let json, _):
                    guard let json = json?.dictionary, let timestamp = json["timestamp"] as? Int else {
                        print("No response json - Fetch timestamp")
                        return
                    }

                    completion(timestamp)
                case .failure(_, let response, _):
                    print(response)
                }
            }
        }
    }

    public func updateUserIfNeeded(_ user: TokenUser) {
        guard let migratedUser = TokenUser.current, user.paymentAddress != migratedUser.paymentAddress else {
            return
        }

        updateUser(migratedUser.asDict) { _, _ in }
    }

    public func registerUserIfNeeded(_ success: @escaping (() -> Void)) {
        retrieveUser(username: Cereal.shared.address) { user in
            guard user == nil else { return }

            self.fetchTimestamp { timestamp in
                let cereal = Cereal.shared
                let path = "/v1/user"
                let parameters = [
                    "payment_address": cereal.paymentAddress
                ]
                let parametersString = String(data: try! JSONSerialization.data(withJSONObject: parameters, options: []), encoding: .utf8)!
                let hashedParameters = cereal.sha3WithID(string: parametersString)
                let signature = "0x\(cereal.signWithID(message: "POST\n\(path)\n\(timestamp)\n\(hashedParameters)"))"

                let fields: [String: String] = ["Token-ID-Address": cereal.address, "Token-Signature": signature, "Token-Timestamp": String(timestamp)]

                let json = RequestParameter(parameters)

                DispatchQueue.global(qos: .userInitiated).async {
                    self.teapot.post(path, parameters: json, headerFields: fields) { result in
                        switch result {
                        case .success(let json, let response):
                            guard response.statusCode == 200 else { return }
                            guard let json = json?.dictionary else { return }

                            TokenUser.createCurrentUser(with: json)

                            success()
                        case .failure(let json, _, let error):
                            print(error)
                            print(json ?? "")
                        }
                    }
                }
            }
        }
    }

    public func updateAvatar(_ avatar: UIImage, completion: @escaping ((_ success: Bool) -> Void)) {
        fetchTimestamp { timestamp in
            let cereal = Cereal.shared
            let path = "/v1/user"
            let boundary = "teapot.boundary"
            let payload = self.teapot.multipartData(from: avatar, boundary: boundary, filename: "avatar.png")
            let hashedPayload = cereal.sha3WithID(data: payload)
            let signature = "0x\(cereal.signWithID(message: "PUT\n\(path)\n\(timestamp)\n\(hashedPayload)"))"

            let fields: [String: String] = ["Token-ID-Address": cereal.address, "Token-Signature": signature, "Token-Timestamp": String(timestamp), "Content-Length": String(describing: payload.count), "Content-Type": "multipart/form-data; boundary=\(boundary)"]
            let json = RequestParameter(payload)

            DispatchQueue.global(qos: .userInitiated).async {
                self.teapot.put(path, parameters: json, headerFields: fields) { result in
                    switch result {
                    case .success(let json, _):
                        guard let userDict = json?.dictionary else {
                            completion(false)
                            return
                        }

                        if let path = userDict["avatar"] as? String {
                            AvatarManager.shared.refreshAvatar(at: path)
                            TokenUser.current?.update(avatar: avatar, avatarPath: path)
                        }

                        completion(true)
                    case .failure(_, _, let error):
                        // TODO: show error
                        print(error)
                        completion(false)
                    }
                }
            }
        }
    }

    public func updateUser(_ userDict: [String: Any], completion: @escaping ((_ success: Bool, _ message: String?) -> Void)) {
        fetchTimestamp { timestamp in
            let cereal = Cereal.shared
            let path = "/v1/user"
            let payload = try! JSONSerialization.data(withJSONObject: userDict, options: [])
            let payloadString = String(data: payload, encoding: .utf8)!

            let hashedPayload = cereal.sha3WithID(string: payloadString)
            let signature = "0x\(cereal.signWithID(message: "PUT\n\(path)\n\(timestamp)\n\(hashedPayload)"))"

            let fields: [String: String] = ["Token-ID-Address": cereal.address, "Token-Signature": signature, "Token-Timestamp": String(timestamp)]
            let json = RequestParameter(userDict)

            DispatchQueue.global(qos: .userInitiated).async {
                self.teapot.put("/v1/user", parameters: json, headerFields: fields) { result in
                    switch result {
                    case .success(let json, let response):
                        guard response.statusCode == 200, let json = json?.dictionary else {
                            print("Invalid response - Update user")
                            completion(false, "Something went wrong")
                            return
                        }

                        TokenUser.current?.update(json: json)

                        completion(true, nil)
                    case .failure(let json, _, _):
                        let errors = json?.dictionary?["errors"] as? [[String: Any]]
                        let message = errors?.first?["message"] as? String
                        completion(false, message)
                    }
                }
            }
        }
    }

    /// Used to retrieve server-side contact data. For the current user, see retrieveUser(username: completion:)
    ///
    /// - Parameters:
    ///   - username: username or id address
    ///   - completion: called on completion
    public func retrieveContact(username: String, completion: @escaping ((TokenUser?) -> Void)) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.teapot.get("/v1/user/\(username)", headerFields: ["Token-Timestamp": String(Int(Date().timeIntervalSince1970))]) { (result: NetworkResult) in
                switch result {
                case .success(let json, _):
                    // we know it's a dictionary for this API
                    guard let json = json?.dictionary else {
                        completion(nil)
                        return
                    }

                    let contact = TokenUser(json: json)

                    completion(contact)
                case .failure(let json, _, let error):
                    print(error.localizedDescription)
                    print(json?.dictionary ?? "")

                    completion(nil)
                }
            }
        }
    }

    /// Used to retrieve the server-side data for the current user. For contacts use retrieveContact(username:completion:)
    ///
    /// - Parameters:
    ///   - username: username of id address
    ///   - completion: called on completion
    public func retrieveUser(username: String, completion: @escaping ((TokenUser?) -> Void)) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.teapot.get("/v1/user/\(username)", headerFields: ["Token-Timestamp": String(Int(Date().timeIntervalSince1970))]) { (result: NetworkResult) in
                switch result {
                case .success(let json, _):
                    // we know it's a dictionary for this API
                    guard let json = json?.dictionary else {
                        completion(nil)
                        return
                    }

                    let user: TokenUser?

                    if let address = json[TokenUser.Constants.address] as? String, Cereal.shared.address == address {
                        TokenUser.current?.update(json: json)
                        user = TokenUser.current

                        print("Current user with address: \(String(describing: user?.address))")

                    } else {
                        user = TokenUser(json: json)
                    }

                    completion(user)
                case .failure(let json, let response, let error):
                    print(error.localizedDescription)
                    print(response)
                    print(json?.dictionary ?? "")
                    
                    completion(nil)
                }
            }
        }
    }

    public func findContact(name: String, completion: @escaping ((TokenUser?) -> Void)) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.teapot.get("/v1/user/\(name)") { (result: NetworkResult) in
                var contact: TokenUser?

                switch result {
                case .success(let json, _):
                    guard let json = json?.dictionary else {
                        completion(nil)
                        return
                    }

                    contact = TokenUser(json: json)
                    NotificationCenter.default.post(name: IDAPIClient.didFetchContactInfoNotification, object: contact)
                case .failure(_, _, let error):
                    print(error.localizedDescription)
                }

                completion(contact)
            }
        }

        contactCache.setObject(forKey: name, cacheBlock: { success, failure in

            DispatchQueue.global(qos: .userInitiated).async {
                self.teapot.get("/v1/user/\(name)") { (result: NetworkResult) in
                    switch result {
                    case .success(let json, _):
                        guard let json = json?.dictionary else {
                            completion(nil)
                            return
                        }

                        let contact = TokenUser(json: json)
                        NotificationCenter.default.post(name: IDAPIClient.didFetchContactInfoNotification, object: contact)

                        success(contact, self.cacheExpiry)
                    case .failure(_, _, let error):
                        print(error.localizedDescription)

                        failure(error as NSError)
                    }
                }
            }
        }) { contact, _, _ in
            completion(contact)
        }
    }

    public func searchContacts(name: String, completion: @escaping (([TokenUser]) -> Void)) {

        DispatchQueue.global(qos: .userInitiated).async {
            let query = name.addingPercentEncoding(withAllowedCharacters: IDAPIClient.allowedSearchTermCharacters) ?? name
            self.teapot.get("/v1/search/user?query=\(query)") { (result: NetworkResult) in
                switch result {
                case .success(let json, _):
                    guard let dictionary = json?.dictionary, var json = dictionary["results"] as? [[String: Any]] else {
                        completion([])
                        return
                    }

                    var contacts = [TokenUser]()
                    json = json.filter { item -> Bool in
                        guard let address = item[TokenUser.Constants.address] as? String else { return true }
                        return address != Cereal.shared.address
                    }

                    for item in json {
                        contacts.append(TokenUser(json: item))
                    }
                    completion(contacts)
                case .failure(_, _, let error):
                    print(error.localizedDescription)
                    completion([])
                }
            }
        }
    }

    public func getTopRatedPublicUsers(limit: Int = 10, completion: @escaping (_ apps: [TokenUser]?, _ error: Error?) -> Void) {

        DispatchQueue.global(qos: .userInitiated).async {
            self.teapot.get("/v1/search/user?public=true&top=true&recent=false&limit=\(limit)") { (result: NetworkResult) in
                switch result {
                case .success(let json, _):
                    guard let dictionary = json?.dictionary, let json = dictionary["results"] as? [[String: Any]] else {
                        completion([], nil)
                        return
                    }

                    let contacts = json.map { userJSON in
                        TokenUser(json: userJSON)
                    }
                    completion(contacts, nil)
                case .failure(_, _, let error):
                    print(error.localizedDescription)
                    completion([], error)
                }
            }
        }
    }

    public func getLatestPublicUsers(limit: Int = 10, completion: @escaping (_ apps: [TokenUser]?, _ error: Error?) -> Void) {

        DispatchQueue.global(qos: .userInitiated).async {
            self.teapot.get("/v1/search/user?public=true&top=false&recent=true&limit=\(limit)") { (result: NetworkResult) in
                switch result {
                case .success(let json, _):
                    guard let dictionary = json?.dictionary, let json = dictionary["results"] as? [[String: Any]] else {
                        completion([], nil)
                        return
                    }

                    let contacts = json.map { userJSON in
                        TokenUser(json: userJSON)
                    }
                    completion(contacts, nil)
                case .failure(_, _, let error):
                    print(error.localizedDescription)
                    completion([], error)
                }
            }
        }
    }

    public func reportUser(address: String, reason: String = "", completion: ((_ success: Bool, _ message: String) -> Void)? = nil) {
        fetchTimestamp { timestamp in
            let cereal = Cereal.shared
            let path = "/v1/report"

            let payload = [
                "token_id": address,
                "details": reason
            ]
            let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [])
            let payloadString = String(data: payloadData, encoding: .utf8)!
            let hashedPayload = cereal.sha3WithID(string: payloadString)
            let signature = "0x\(cereal.signWithID(message: "POST\n\(path)\n\(timestamp)\n\(hashedPayload)"))"

            let fields: [String: String] = ["Token-ID-Address": cereal.address, "Token-Signature": signature, "Token-Timestamp": String(timestamp)]
            let json = RequestParameter(payload)

            DispatchQueue.global(qos: .userInitiated).async {

                self.teapot.post(path, parameters: json, headerFields: fields) { result in
                    switch result {
                    case .success(_, let response):
                        guard response.statusCode == 204 else {
                            print("Invalid response - Report user")
                            completion?(false, "Something went wrong")
                            return
                        }

                        completion?(true, "")
                    case .failure(let json, _, _):
                        let errors = json?.dictionary?["errors"] as? [[String: Any]]
                        let message = errors?.first?["message"] as? String

                        completion?(false, message ?? "")
                    }
                }
            }
        }
    }

    public func login(login_token: String, completion: ((_ success: Bool, _ message: String) -> Void)? = nil) {
        fetchTimestamp { timestamp in
            let cereal = Cereal.shared
            let path = "/v1/login/\(login_token)"

            let signature = "0x\(cereal.signWithID(message: "GET\n\(path)\n\(timestamp)\n"))"

            let fields: [String: String] = ["Token-ID-Address": cereal.address, "Token-Signature": signature, "Token-Timestamp": String(timestamp)]

            DispatchQueue.global(qos: .userInitiated).async {
                self.teapot.get(path, headerFields: fields) { result in
                    switch result {
                    case .success(_, let response):
                        guard response.statusCode == 204 else {
                            print("Invalid response - Login")
                            completion?(false, "Something went wrong")
                            return
                        }

                        completion?(true, "")
                    case .failure(let json, _, _):
                        let errors = json?.dictionary?["errors"] as? [[String: Any]]
                        let message = errors?.first?["message"] as? String

                        completion?(false, message ?? "")
                    }
                }
            }
        }
    }
}
