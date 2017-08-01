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
import KeychainSwift

protocol Singleton: class {
    static var sharedInstance: Self { get }
}

fileprivate struct UserDB {

    static let password = "DBPWD"

    static let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

    static let dbFile = ".Signal.sqlite"
    static let walFile = ".Signal.sqlite-wal"
    static let shmFile = ".Signal.sqlite-shm"

    static let dbFilePath = documentsUrl.appendingPathComponent(dbFile).path
    static let walFilePath = documentsUrl.appendingPathComponent(walFile).path
    static let shmFilePath = documentsUrl.appendingPathComponent(shmFile).path

    struct Backup {
        static let directory = "UserDB-Backup"
        static let directoryPath = documentsUrl.appendingPathComponent(directory).path

        static let dbFile = ".Signal-Backup.sqlite"
        static let dbFilePath = documentsUrl.appendingPathComponent(directory).appendingPathComponent(".Signal-Backup-\(Cereal.shared.address).sqlite").path
    }
}

public final class Yap: NSObject, Singleton {
    var database: YapDatabase?

    public var mainConnection: YapDatabaseConnection?

    public static let sharedInstance = Yap()
    public static var isCurrentUserDataAccessible: Bool {
        return KeychainSwift().getData(UserDB.password) != nil
    }

    private override init() {
        super.init()

        let options = YapDatabaseOptions()
        options.corruptAction = .fail

        let keychain = KeychainSwift()
        keychain.synchronizable = false

        if Yap.isCurrentUserDataAccessible {
            options.cipherKeyBlock = {
                let keychain = KeychainSwift()
                keychain.synchronizable = false

                return keychain.getData(UserDB.password)!
            }

            database = YapDatabase(path: UserDB.dbFilePath, options: options)

            print("\n\n------ ------ ------ \n *** DATABASE CREATED *** \n------ ------ ------ \n\n")

            let url = NSURL(fileURLWithPath: UserDB.dbFilePath)
            try! url.setResourceValue(false, forKey: .isUbiquitousItemKey)
            try! url.setResourceValue(true, forKey: .isExcludedFromBackupKey)

            mainConnection = database?.newConnection()
        }
    }

     public func setupForNewUser(with address: String) {
        let options = YapDatabaseOptions()
        options.corruptAction = .fail

        let keychain = KeychainSwift()
        keychain.synchronizable = false

        print(try! FileManager.default.contentsOfDirectory(atPath: UserDB.documentsUrl.path))

        useBackedDBIfNeeded()

        var dbPassowrd: Data
        if let loggedData = keychain.getData(UserDB.password) as Data? {
            dbPassowrd = loggedData
        } else {
            if keychain.getData(address) != nil {
                print("\n||----------------\n||\n|| Retrieving DB Password for address: \(address) \n||\n||----------------")
            }
           dbPassowrd = keychain.getData(address) ?? Randomness.generateRandomBytes(60).base64EncodedString().data(using: .utf8)!
        }
        keychain.set(dbPassowrd, forKey: UserDB.password, withAccess: .accessibleAfterFirstUnlockThisDeviceOnly)

        options.cipherKeyBlock = {
            let keychain = KeychainSwift()
            keychain.synchronizable = false

            return keychain.getData(UserDB.password)!
        }

        database = YapDatabase(path: UserDB.dbFilePath, options: options)

        print("\n||------------------- \n||\n||\n|| *** DATABASE CREATED for user with address: \(address) *** \n||\n||\n||-------------------\n")

        let url = NSURL(fileURLWithPath: UserDB.dbFilePath)
        try! url.setResourceValue(false, forKey: .isUbiquitousItemKey)
        try! url.setResourceValue(true, forKey: .isExcludedFromBackupKey)

        mainConnection = database?.newConnection()

        self.insert(object: TokenUser.current?.JSONData, for: TokenUser.storedUserKey)

        createBackupDirectoryIfNeeded()
    }

    public func wipeStorage() {
        if TokenUser.current?.verified == false {
            do {
                KeychainSwift().delete(UserDB.password)
                print("\n|| Deleted DB password from keychain\n||\n||------------------------------------")

                print("\n||\n|| --- User not verified, deleting DB file \n||\n||")
                
                self.deleteFileIfNeeded(at: UserDB.dbFilePath)
                self.deleteFileIfNeeded(at: UserDB.walFilePath)
                self.deleteFileIfNeeded(at: UserDB.shmFilePath)
            } catch {}

            return
        }

        backupUserDBFile()
    }

    fileprivate func createBackupDirectoryIfNeeded() {
        createdDirectoryIfNeeded(at: UserDB.Backup.directoryPath)
    }

    fileprivate func createdDirectoryIfNeeded(at path: String) {
        if FileManager.default.fileExists(atPath: path) == false {
            do {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: nil)
            } catch {}
        }
    }

    fileprivate func useBackedDBIfNeeded() {
        if TokenUser.current != nil, FileManager.default.fileExists(atPath: UserDB.Backup.dbFilePath) {
            do {
                print("\n|| --------------------\n||\n|| --- Using Backup: DB file path: \(UserDB.Backup.dbFilePath)\n||\n||")
                print("\n|| --- Item moving ... \n|| --- Content of  backed path for user: \(try FileManager.default.contentsOfDirectory(atPath: UserDB.Backup.directoryPath))\n||")

                try FileManager.default.moveItem(atPath: UserDB.Backup.dbFilePath, toPath: UserDB.dbFilePath)

                print("\n|| --- Item moved ... \n|| --- Content of  backed path for user: \(try FileManager.default.contentsOfDirectory(atPath: UserDB.Backup.directoryPath))\n||\n|| --------------------")
            } catch {
                print("\n|| --- Something went wrong while moving to BACKUP PATH\n||\n||----------------\n||\n")
            }
        }
    }

    fileprivate func deleteFileIfNeeded(at path: String) {
        if FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {}
        }
    }

    fileprivate func backupUserDBFile() {
        guard let user = TokenUser.current as TokenUser? else { return }

        print("\n||------------------------------------\n|| Wiping DB file for user: \(user.username)\n||")

        deleteFileIfNeeded(at: UserDB.walFilePath)
        deleteFileIfNeeded(at: UserDB.shmFilePath)

        let keychain = KeychainSwift()
        let currentPassword = keychain.getData(UserDB.password)!

        print("\n|| Current user DB password: \(currentPassword.base64EncodedString())\n||")
        keychain.set(currentPassword, forKey: user.address)
        print("\n|| Setting DB password for key: \(user.address)")

        do {
            print("\n||\n|| --- Backup DB path for user: \(UserDB.Backup.dbFilePath)\n||\n||")
            print("\n|| --- Storage being wiped...\n||Content of  backed path for user: \(try FileManager.default.contentsOfDirectory(atPath: UserDB.Backup.directoryPath))\n||")
            try FileManager.default.moveItem(atPath: UserDB.dbFilePath, toPath: UserDB.Backup.dbFilePath)
            print("\n||\n|| --- Storage wiped...\n||Content of  backed path for user: \(try FileManager.default.contentsOfDirectory(atPath: UserDB.Backup.directoryPath))\n||")
        } catch {}

        KeychainSwift().delete(UserDB.password)
        print("\n|| Deleted DB password from keychain\n||\n||------------------------------------")
    }

    /// Insert a object into the database using the main thread default connection.
    ///
    /// - Parameters:
    ///   - object: Object to be stored. Must be serialisable. If nil, delete the record from the database.
    ///   - key: Key to store and retrieve object.
    ///   - collection: Optional. The name of the collection the object belongs to. Helps with organisation.
    ///   - metadata: Optional. Any serialisable object. Could be a related object, a description, a timestamp, a dictionary, and so on.
    public final func insert(object: Any?, for key: String, in collection: String? = nil, with metadata: Any? = nil) {
        mainConnection?.asyncReadWrite { transaction in
            transaction.setObject(object, forKey: key, inCollection: collection, withMetadata: metadata)
        }
    }

    public final func removeObject(for key: String, in collection: String? = nil) {
        mainConnection?.asyncReadWrite { transaction in
            transaction.removeObject(forKey: key, inCollection: collection)
        }
    }

    /// Checks whether an object was stored for a given key inside a given (optional) collection.
    ///
    /// - Parameter key: Key to check for the presence of a stored object.
    /// - Returns: Bool whether or not a certain object was stored for that key.
    public final func containsObject(for key: String, in collection: String? = nil) -> Bool {
        return retrieveObject(for: key, in: collection) != nil
    }

    /// Retrieve an object for a given key inside a given (optional) collection.
    ///
    /// - Parameters:
    ///   - key: Key used to store the object
    ///   - collection: Optional. The name of the collection the object was stored in.
    /// - Returns: The stored object.
    public final func retrieveObject(for key: String, in collection: String? = nil) -> Any? {
        var object: Any?
        mainConnection?.read { transaction in
            object = transaction.object(forKey: key, inCollection: collection)
        }

        return object
    }

    /// Retrieve all objects from a given collection.
    ///
    /// - Parameters:
    ///   - collection: The name of the collection to be retrieved.
    /// - Returns: The stored objects inside the collection.
    public final func retrieveObjects(in collection: String) -> [Any] {
        var objects = [Any]()

        mainConnection?.read { transaction in
            transaction.enumerateKeysAndObjects(inCollection: collection) { _, object, _ in
                objects.append(object)
            }
        }

        return objects
    }
}
