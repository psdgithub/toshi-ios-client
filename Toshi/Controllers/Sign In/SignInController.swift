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

open class SignInController: UIViewController {

    fileprivate var idAPIClient: IDAPIClient {
        return IDAPIClient.shared
    }

    private lazy var scrollView: UIScrollView = {
        let view = UIScrollView(withAutoLayout: true)
        view.alwaysBounceVertical = true
        view.delaysContentTouches = false

        return view
    }()

    private lazy var contentView: UIView = {
        let view = UIView(withAutoLayout: true)

        return view
    }()

    private lazy var usernameField: InputField = {
        InputField(type: .username)
    }()

    private lazy var passwordField: InputField = {
        let field = InputField(type: .password)
        field.textField.autocapitalizationType = .none

        return field
    }()

    private lazy var footnote: Footnote = {
        Footnote(text: "This is your 12 word phrase, separated by spaces")
    }()

    private lazy var signInButton: ActionButton = {
        let view = ActionButton(margin: 30)
        view.title = "Sign in"
        view.addTarget(self, action: #selector(signInWithPasshphrase), for: .touchUpInside)

        return view
    }()

    public required init?(coder _: NSCoder) {
        fatalError("")
    }

    public init() {
        super.init(nibName: nil, bundle: nil)

        title = "Sign in"
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.settingsBackgroundColor

        self.addSubviewsAndConstraints()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.tap(_:)))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    func tap(_: UITapGestureRecognizer) {
        usernameField.textField.resignFirstResponder()
        passwordField.textField.resignFirstResponder()
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.setNavigationBarHidden(false, animated: true)
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        navigationController?.setNavigationBarHidden(true, animated: true)
    }

    private func addSubviewsAndConstraints() {

        let margin: CGFloat = 16

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(usernameField)
        contentView.addSubview(passwordField)
        contentView.addSubview(footnote)
        contentView.addSubview(signInButton)

        NSLayoutConstraint.activate([
            self.scrollView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.scrollView.leftAnchor.constraint(equalTo: self.view.leftAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.scrollView.rightAnchor.constraint(equalTo: self.view.rightAnchor),

            self.contentView.topAnchor.constraint(equalTo: self.scrollView.topAnchor),
            self.contentView.leftAnchor.constraint(equalTo: self.scrollView.leftAnchor),
            self.contentView.bottomAnchor.constraint(equalTo: self.scrollView.bottomAnchor),
            self.contentView.rightAnchor.constraint(equalTo: self.scrollView.rightAnchor),
            self.contentView.widthAnchor.constraint(equalTo: self.scrollView.widthAnchor),

            self.usernameField.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 20),
            self.usernameField.leftAnchor.constraint(equalTo: self.contentView.leftAnchor),
            self.usernameField.rightAnchor.constraint(equalTo: self.contentView.rightAnchor),
            self.usernameField.heightAnchor.constraint(equalToConstant: InputField.height),

            self.passwordField.topAnchor.constraint(equalTo: self.usernameField.bottomAnchor),
            self.passwordField.leftAnchor.constraint(equalTo: self.contentView.leftAnchor),
            self.passwordField.rightAnchor.constraint(equalTo: self.contentView.rightAnchor),
            self.passwordField.heightAnchor.constraint(equalToConstant: InputField.height),

            self.usernameField.titleLabel.widthAnchor.constraint(equalTo: self.passwordField.titleLabel.widthAnchor).priority(.high),

            self.footnote.topAnchor.constraint(equalTo: self.passwordField.bottomAnchor, constant: 10),
            self.footnote.leftAnchor.constraint(equalTo: self.contentView.leftAnchor, constant: margin),
            self.footnote.rightAnchor.constraint(equalTo: self.contentView.rightAnchor, constant: -margin),

            self.signInButton.topAnchor.constraint(equalTo: self.footnote.bottomAnchor, constant: margin * 2),
            self.signInButton.leftAnchor.constraint(equalTo: self.contentView.leftAnchor, constant: margin),
            self.signInButton.rightAnchor.constraint(equalTo: self.contentView.rightAnchor, constant: -margin),
            self.signInButton.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor)
        ])
    }

    func signInWithPasshphrase() {
        guard let passphrase = self.passwordField.textField.text?.lowercased() else {
            return
        }

        let words = passphrase.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
        guard words.count == 12 else {
            let alert = UIAlertController.dismissableAlert(title: "Invalid passphrase", message: "Make sure your backup phrase consists of 12 words, separated by a single space.")
            Navigator.presentModally(alert)

            return
        }

        guard let cereal = Cereal(words: words) else {
            let alert = UIAlertController.dismissableAlert(title: "Invalid passphrase", message: "Are you sure you typed your backup phrase correctly?")
            Navigator.presentModally(alert)

            return
        }

        let idClient = IDAPIClient.shared
        idClient.retrieveUser(username: cereal.address) { user in
            if let user = user {
                Cereal.shared = cereal
                UserDefaults.standard.set(false, forKey: RequiresSignIn)

                user.updateVerificationState(true)
                TokenUser.createCurrentUser(with: user.asDict)

                ChatAPIClient.shared.registerUser()

                guard let delegate = UIApplication.shared.delegate as? AppDelegate else { return }
                delegate.signInUser()

                self.navigationController?.dismiss(animated: true, completion: nil)
            } else {
                let alert = UIAlertController.dismissableAlert(title: Localized("No such user"))
                Navigator.presentModally(alert)
            }
        }
    }
}
