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
import SweetUIKit
import CoreImage

class QRCodeController: UIViewController {

    static let addUsernameBasePath = "https://app.tokenbrowser.com/add/"
    static let addUserPath = "/add/"
    static let paymentWithUsernamePath = "/pay/"
    static let paymentWithAddressPath = "/ethereum:"

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }

    private lazy var qrCodeImageView: UIImageView = UIImageView()

    private lazy var nameLabel: UILabel = {
        let view = UILabel()
        view.font = Theme.light(size: 35)
        view.textAlignment = .center
        view.adjustsFontSizeToFitWidth = true
        view.minimumScaleFactor = 0.3

        return view
    }()

    private lazy var usernameLabel: UILabel = {
        let view = UILabel()
        view.font = Theme.regular(size: 16)
        view.textAlignment = .center
        view.adjustsFontSizeToFitWidth = true
        view.minimumScaleFactor = 0.6

        return view
    }()

    convenience init(for username: String, name: String) {
        self.init(nibName: nil, bundle: nil)

        title = "My QR Code"

        qrCodeImageView.image = UIImage.imageQRCode(for: "\(QRCodeController.addUsernameBasePath)\(username)", resizeRate: 20.0)
        usernameLabel.text = username
        nameLabel.text = name
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.settingsBackgroundColor
        view.addSubview(qrCodeImageView)
        view.addSubview(nameLabel)
        view.addSubview(usernameLabel)

        let top = navigationController?.navigationBar.frame.height ?? 0

        qrCodeImageView.height(300)
        qrCodeImageView.width(300)
        qrCodeImageView.centerX(to: view)
        qrCodeImageView.centerY(to: view, offset: -top)

        nameLabel.height(42)
        nameLabel.topToBottom(of: qrCodeImageView, offset: 16)
        nameLabel.left(to: view, offset: 16)
        nameLabel.right(to: view, offset: -16)

        usernameLabel.height(24)
        usernameLabel.topToBottom(of: nameLabel, offset: 6)
        usernameLabel.left(to: view, offset: 16)
        usernameLabel.right(to: view, offset: -16)
    }
}

extension QRCodeController: UIToolbarDelegate {

    func position(for _: UIBarPositioning) -> UIBarPosition {
        return .topAttached
    }
}
