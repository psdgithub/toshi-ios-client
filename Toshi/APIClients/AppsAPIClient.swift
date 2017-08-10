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
import AwesomeCache
import Teapot
import UIKit

public class AppsAPIClient: NSObject, CacheExpiryDefault {
    static let shared: AppsAPIClient = AppsAPIClient()

    private var teapot: Teapot

    private var imageCache = try! Cache<UIImage>(name: "appImageCache")

    override init() {
        teapot = Teapot(baseURL: URL(string: TokenDirectoryServiceBaseURLPath)!)
    }

    convenience init(mockTeapot: MockTeapot) {
        self.init()
        self.teapot = mockTeapot
    }


    func getTopRatedApps(limit: Int = 10, completion: @escaping (_ apps: [TokenUser]?, _ error: Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.teapot.get("/v1/search/apps?top=true&recent=false&limit=\(limit)") { (result: NetworkResult) in
                switch result {

                case .success(let json, _):
                    guard let json = json?.dictionary, let appsJSON = json["results"] as? [[String: Any]] else {
                        completion(nil, nil)
                        return
                    }

                    let apps = appsJSON.map { json -> TokenUser in
                        let app = TokenUser(json: json)

                        return app
                    }

                    completion(apps, nil)
                case .failure(_, _, let error):
                    completion([TokenUser](), error)
                }
            }
        }
    }

    func getFeaturedApps(limit: Int = 10, completion: @escaping (_ apps: [TokenUser]?, _ error: Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.teapot.get("/v1/search/apps?top=false&recent=true&limit=\(limit)") { (result: NetworkResult) in
                switch result {

                case .success(let json, _):
                    guard let json = json?.dictionary, let appsJSON = json["results"] as? [[String: Any]] else {
                        completion(nil, nil)
                        return
                    }

                    let apps = appsJSON.map { json -> TokenUser in
                        let app = TokenUser(json: json)

                        return app
                    }

                    completion(apps, nil)
                case .failure(_, _, let error):
                    completion([TokenUser](), error)
                }
            }
        }
    }

    func search(_ searchTerm: String, limit: Int = 100, completion: @escaping (_ apps: [TokenUser], _ error: Error?) -> Void) {
        guard !searchTerm.isEmpty else {
            completion([TokenUser](), nil)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let query = searchTerm.addingPercentEncoding(withAllowedCharacters: IDAPIClient.allowedSearchTermCharacters) ?? searchTerm
            self.teapot.get("/v1/search/apps/?query=\(query)&limit=\(limit)") { (result: NetworkResult) in
                switch result {
                case .success(let json, _):
                    guard let json = json?.dictionary else {
                        completion([], nil)

                        return
                    }

                    guard let appsJSON = json["results"] as? [[String: Any]] else {
                        completion([TokenUser](), nil)
                        return
                    }

                    let apps = appsJSON.map { json -> TokenUser in
                        return TokenUser(json: json)
                    }

                    completion(apps, nil)
                case .failure(_, let response, let error):
                    if response.statusCode == 404 {
                        completion([TokenUser](), nil)
                    } else {
                        completion([TokenUser](), error)
                    }
                }
            }
        }
    }
}
