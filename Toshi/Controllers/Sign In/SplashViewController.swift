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
import UIKit
import SweetUIKit

let logoTopSpace: CGFloat = 100.0
let logoSize: CGFloat = 54.0

let titleLabelToSpace: CGFloat = 27.0

final class SplashViewController: UIViewController {

    private lazy var backgroundImageView: UIImageView = {
        let imageView = UIImageView(withAutoLayout: true)
        imageView.contentMode = .scaleAspectFill
        imageView.isUserInteractionEnabled = true
        imageView.image = UIImage(named: "splash")

        return imageView
    }()

    private lazy var logoImageView: UIImageView = {
        let imageView = UIImageView(withAutoLayout: true)
        imageView.contentMode = .center
        imageView.image = UIImage(named: "logo")

        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel(withAutoLayout: true)
        label.font = Theme.regular(size: 43.0)
        label.textAlignment = .center
        label.textColor = Theme.viewBackgroundColor
        label.numberOfLines = 0
        label.text = "Welcome to\nToshi"

        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel(withAutoLayout: true)
        label.font = Theme.regular(size: 17.0)
        label.textColor = Theme.viewBackgroundColor.withAlphaComponent(0.6)
        label.numberOfLines = 0

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 5
        paragraphStyle.alignment = .center

        let attrString = NSMutableAttributedString(string: "A browser for the Ethereum network\nthat provides universal access to\nfinancial services")
        attrString.addAttribute(NSParagraphStyleAttributeName, value: paragraphStyle, range: NSRange(location: 0, length: attrString.length))

        label.attributedText = attrString

        return label
    }()

    private lazy var signinButton: UIButton = {
        let button = UIButton(withAutoLayout: true)
        button.isUserInteractionEnabled = true
        button.setTitle("Sign in", for: .normal)
        button.setTitleColor(Theme.viewBackgroundColor, for: .normal)
        button.addTarget(self, action: #selector(signinPressed(_:)), for: .touchUpInside)
        button.titleLabel?.font = Theme.regular(size: 16.0)

        return button
    }()

    private lazy var newAccountButton: UIButton = {
        let button = UIButton(withAutoLayout: true)
        button.setTitle("Create a new account", for: .normal)
        button.setTitleColor(Theme.viewBackgroundColor, for: .normal)
        button.addTarget(self, action: #selector(newAccountPressed(_:)), for: .touchUpInside)
        button.titleLabel?.font = Theme.regular(size: 20.0)

        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        decorateView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        UIView.animate(withDuration: 0.2) {
            self.view.alpha = 1.0
        }
    }

    private func decorateView() {
        view.addSubview(backgroundImageView)
        backgroundImageView.fillSuperview()

        backgroundImageView.addSubview(logoImageView)
        logoImageView.topAnchor.constraint(equalTo: backgroundImageView.topAnchor, constant: logoTopSpace).isActive = true
        logoImageView.centerXAnchor.constraint(equalTo: backgroundImageView.centerXAnchor).isActive = true
        logoImageView.set(height: logoSize)
        logoImageView.set(width: logoSize)

        backgroundImageView.addSubview(titleLabel)
        titleLabel.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: 24.0).isActive = true
        titleLabel.centerXAnchor.constraint(equalTo: backgroundImageView.centerXAnchor).isActive = true

        backgroundImageView.addSubview(subtitleLabel)
        subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20.0).isActive = true
        subtitleLabel.centerXAnchor.constraint(equalTo: backgroundImageView.centerXAnchor).isActive = true

        backgroundImageView.addSubview(signinButton)
        signinButton.set(width: 70.0)
        signinButton.set(height: 44.0)
        signinButton.centerXAnchor.constraint(equalTo: backgroundImageView.centerXAnchor).isActive = true
        signinButton.bottomAnchor.constraint(equalTo: backgroundImageView.bottomAnchor, constant: -40.0).isActive = true

        backgroundImageView.addSubview(newAccountButton)
        newAccountButton.set(height: 44.0)
        newAccountButton.centerXAnchor.constraint(equalTo: backgroundImageView.centerXAnchor).isActive = true
        newAccountButton.bottomAnchor.constraint(equalTo: signinButton.topAnchor, constant: -20.0).isActive = true

        view.alpha = 0.0
    }

    @objc private func signinPressed(_: UIButton) {
        let controller = SignInController()
        Navigator.push(controller, from: self)
    }

    @objc private func newAccountPressed(_: UIButton) {
        dismiss(animated: true) {
            (UIApplication.shared.delegate as? AppDelegate)?.createNewUser()
        }
    }
}
