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

public class ContactController: UIViewController {

    fileprivate lazy var activityView: UIActivityIndicatorView = {
        self.defaultActivityIndicator()
    }()

    public var contact: TokenUser

    fileprivate var idAPIClient: IDAPIClient {
        return IDAPIClient.shared
    }

    fileprivate var messageSender: MessageSender? {
        let appDelegate = UIApplication.shared.delegate as? AppDelegate

        return appDelegate?.messageSender
    }

    lazy var avatarImageView: AvatarImageView = {
        let view = AvatarImageView(withAutoLayout: true)

        return view
    }()

    lazy var nameLabel: UILabel = {
        let view = UILabel(withAutoLayout: true)
        view.numberOfLines = 0
        view.font = Theme.regular(size: 24)

        return view
    }()

    lazy var usernameLabel: UILabel = {
        let view = UILabel(withAutoLayout: true)
        view.numberOfLines = 0
        view.font = Theme.regular(size: 16)
        view.textColor = Theme.greyTextColor

        return view
    }()

    lazy var aboutContentLabel: UILabel = {
        let view = UILabel(withAutoLayout: true)
        view.font = Theme.regular(size: 17)
        view.numberOfLines = 0

        return view
    }()

    lazy var locationContentLabel: UILabel = {
        let view = UILabel(withAutoLayout: true)
        view.font = Theme.regular(size: 16)
        view.textColor = Theme.lightGreyTextColor
        view.numberOfLines = 0

        return view
    }()

    lazy var actionsSeparatorView: UIView = {
        let view = UIView(withAutoLayout: true)
        view.backgroundColor = Theme.borderColor
        view.set(height: 1.0 / UIScreen.main.scale)

        return view
    }()

    lazy var actionView: ContactActionView = {
        let view = ContactActionView()

        view.messageButton.addTarget(self, action: #selector(self.didTapMessageContactButton), for: .touchUpInside)
        view.addFavoriteButton.addTarget(self, action: #selector(self.didTapAddContactButton), for: .touchUpInside)
        view.payButton.addTarget(self, action: #selector(self.didTapPayButton), for: .touchUpInside)

        return view
    }()

    lazy var contentBackgroundView: UIView = {
        let view = UIView(withAutoLayout: true)
        view.backgroundColor = Theme.viewBackgroundColor

        return view
    }()

    lazy var topSeparatorView: UIView = {
        let view = UIView(withAutoLayout: true)
        view.backgroundColor = Theme.settingsBackgroundColor
        view.layer.borderColor = Theme.borderColor.cgColor
        view.layer.borderWidth = 1.0 / UIScreen.main.scale
        view.set(height: 1.0 / UIScreen.main.scale)

        return view
    }()

    lazy var reputationSeparatorView: UIView = {
        let view = UIView(withAutoLayout: true)
        view.backgroundColor = Theme.settingsBackgroundColor
        view.layer.borderColor = Theme.borderColor.cgColor
        view.layer.borderWidth = 1.0 / UIScreen.main.scale
        view.set(height: 1.0 / UIScreen.main.scale)

        return view
    }()

    lazy var reputationTitle: UILabel = {
        let view = UILabel(withAutoLayout: true)
        view.font = Theme.regular(size: 13)
        view.textColor = Theme.sectionTitleColor
        view.text = "REPUTATION"

        return view
    }()

    lazy var bottomSeparatorView: UIView = {
        let view = UIView(withAutoLayout: true)
        view.backgroundColor = Theme.settingsBackgroundColor
        view.layer.borderColor = Theme.borderColor.cgColor
        view.layer.borderWidth = 1.0 / UIScreen.main.scale
        view.set(height: 1.0 / UIScreen.main.scale)

        return view
    }()

    lazy var reputationView: ReputationView = {
        let view = ReputationView(withAutoLayout: true)

        return view
    }()

    lazy var rateThisUserButton: UIButton = {
        let view = UIButton(withAutoLayout: true)
        view.setTitle("Rate this user", for: .normal)
        view.setTitleColor(Theme.tintColor, for: .normal)
        view.setTitleColor(Theme.greyTextColor, for: .highlighted)
        view.titleLabel?.font = Theme.regular(size: 17)

        view.addTarget(self, action: #selector(self.didTapRateUser), for: .touchUpInside)

        return view
    }()

    lazy var reputationBackgroundView: UIView = {
        let view = UIView(withAutoLayout: true)
        view.backgroundColor = Theme.viewBackgroundColor

        return view
    }()

    public init(contact: TokenUser) {
        self.contact = contact

        super.init(nibName: nil, bundle: nil)

        edgesForExtendedLayout = .bottom
        title = "Contact"
    }

    public required init?(coder _: NSCoder) {
        fatalError("")
    }

    open override func loadView() {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true

        view = scrollView
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        setupActivityIndicator()

        navigationItem.rightBarButtonItem = UIBarButtonItem(image: #imageLiteral(resourceName: "more"), style: .plain, target: self, action: #selector(displayActions))
        view.backgroundColor = Theme.settingsBackgroundColor

        addSubviewsAndConstraints()

        reputationView.setScore(.zero)
        updateReputation()
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if contact.name.isEmpty {
            usernameLabel.text = nil
            nameLabel.text = contact.displayUsername
        } else {
            nameLabel.text = contact.name
            usernameLabel.text = contact.displayUsername
        }

        aboutContentLabel.text = contact.about
        locationContentLabel.text = contact.location

        if let path = self.contact.avatarPath as String? {
            AvatarManager.shared.avatar(for: path) { image, _ in
                if image != nil {
                    self.avatarImageView.image = image
                }
            }
        }

        updateButton()
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard let scrollView = self.view as? UIScrollView else { return }
        scrollView.contentSize.height = bottomSeparatorView.frame.maxY
    }

    func addSubviewsAndConstraints() {
        view.addSubview(reputationBackgroundView)
        view.addSubview(contentBackgroundView)

        view.addSubview(avatarImageView)
        view.addSubview(nameLabel)
        view.addSubview(usernameLabel)
        view.addSubview(aboutContentLabel)
        view.addSubview(locationContentLabel)

        view.addSubview(actionsSeparatorView)
        view.addSubview(actionView)

        view.addSubview(topSeparatorView)

        view.addSubview(reputationTitle)

        view.addSubview(reputationSeparatorView)

        view.addSubview(reputationView)
        view.addSubview(rateThisUserButton)
        view.addSubview(bottomSeparatorView)

        let height: CGFloat = 26.0
        let marginHorizontal: CGFloat = 16.0
        let marginVertical: CGFloat = 14.0
        let itemSpacing: CGFloat = 8.0
        let avatarSize: CGFloat = 60.0

        avatarImageView.set(height: avatarSize)
        avatarImageView.set(width: avatarSize)
        avatarImageView.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor, constant: 28).isActive = true
        avatarImageView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: marginHorizontal).isActive = true

        nameLabel.setContentHuggingPriority(UILayoutPriorityRequired, for: .vertical)
        nameLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 22).isActive = true
        nameLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor).isActive = true
        nameLabel.leftAnchor.constraint(equalTo: avatarImageView.rightAnchor, constant: marginHorizontal).isActive = true
        nameLabel.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -marginHorizontal).isActive = true

        usernameLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 16).isActive = true
        usernameLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: itemSpacing).isActive = true
        usernameLabel.leftAnchor.constraint(equalTo: avatarImageView.rightAnchor, constant: marginHorizontal).isActive = true
        usernameLabel.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -marginHorizontal).isActive = true

        aboutContentLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: height).isActive = true
        aboutContentLabel.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: marginVertical).isActive = true
        aboutContentLabel.leftAnchor.constraint(equalTo: avatarImageView.leftAnchor).isActive = true
        aboutContentLabel.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -marginHorizontal).isActive = true

        locationContentLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: height).isActive = true
        locationContentLabel.topAnchor.constraint(equalTo: aboutContentLabel.bottomAnchor, constant: itemSpacing).isActive = true
        locationContentLabel.leftAnchor.constraint(equalTo: avatarImageView.leftAnchor).isActive = true
        locationContentLabel.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        locationContentLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -marginVertical).isActive = true

        actionsSeparatorView.topAnchor.constraint(equalTo: locationContentLabel.bottomAnchor, constant: marginVertical).isActive = true
        actionsSeparatorView.leftAnchor.constraint(equalTo: avatarImageView.leftAnchor).isActive = true
        actionsSeparatorView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        actionsSeparatorView.bottomAnchor.constraint(equalTo: actionView.topAnchor, constant: -marginVertical).isActive = true

        actionView.set(height: 54)
        actionView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        actionView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true

        contentBackgroundView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        contentBackgroundView.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor).isActive = true
        contentBackgroundView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        contentBackgroundView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        contentBackgroundView.bottomAnchor.constraint(equalTo: topSeparatorView.topAnchor).isActive = true

        // We set the view and separator width cosntraints to be the same, to force the scrollview content size to conform to the window
        // otherwise no view is requiring a width of the window, and the scrollview contentSize will shrink to the smallest
        // possible width that satisfy all other constraints.
        topSeparatorView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        topSeparatorView.topAnchor.constraint(equalTo: actionView.bottomAnchor, constant: marginVertical).isActive = true
        topSeparatorView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        topSeparatorView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true

        reputationTitle.set(height: 18)
        reputationTitle.leftAnchor.constraint(equalTo: view.leftAnchor, constant: marginHorizontal).isActive = true
        reputationTitle.bottomAnchor.constraint(equalTo: reputationSeparatorView.topAnchor, constant: -8.0).isActive = true

        reputationSeparatorView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        reputationSeparatorView.topAnchor.constraint(equalTo: topSeparatorView.bottomAnchor, constant: 66.0).isActive = true
        reputationSeparatorView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        reputationSeparatorView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true

        reputationView.topAnchor.constraint(equalTo: reputationSeparatorView.bottomAnchor, constant: marginVertical).isActive = true
        reputationView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: marginHorizontal).isActive = true
        reputationView.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -marginHorizontal).isActive = true

        rateThisUserButton.set(height: 22)
        rateThisUserButton.topAnchor.constraint(equalTo: reputationView.bottomAnchor, constant: 30).isActive = true
        rateThisUserButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true

        reputationBackgroundView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        reputationBackgroundView.topAnchor.constraint(equalTo: reputationSeparatorView.bottomAnchor).isActive = true
        reputationBackgroundView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        reputationBackgroundView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        reputationBackgroundView.bottomAnchor.constraint(equalTo: bottomSeparatorView.topAnchor).isActive = true

        bottomSeparatorView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        bottomSeparatorView.topAnchor.constraint(equalTo: rateThisUserButton.bottomAnchor, constant: 20).isActive = true
        bottomSeparatorView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        bottomSeparatorView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
    }

    func updateButton() {
        let isContactAdded = Yap.sharedInstance.containsObject(for: contact.address, in: TokenUser.favoritesCollectionKey)
        let fontColor = isContactAdded ? Theme.tintColor : Theme.lightGreyTextColor
        let title = isContactAdded ? "Favorited" : "Favorite"

        actionView.addFavoriteButton.titleLabel.text = title
        actionView.addFavoriteButton.tintColor = fontColor
    }

    @objc private func didTapMessageContactButton() {
        // create thread if needed
        ChatsInteractor.getOrCreateThread(for: contact.address)

        DispatchQueue.main.async {
            (self.tabBarController as? TabBarController)?.displayMessage(forAddress: self.contact.address)

            if let navController = self.navigationController as? BrowseNavigationController {
                _ = navController.popToRootViewController(animated: false)
            }
        }
    }

    @objc private func didTapAddContactButton() {
        if Yap.sharedInstance.containsObject(for: contact.address, in: TokenUser.favoritesCollectionKey) {
            Yap.sharedInstance.removeObject(for: contact.address, in: TokenUser.favoritesCollectionKey)

            updateButton()
        } else {
            Yap.sharedInstance.insert(object: contact.JSONData, for: contact.address, in: TokenUser.favoritesCollectionKey)
            SoundPlayer.playSound(type: .addedContact)
            updateButton()
        }
    }

    @objc private func didTapPayButton() {
        let paymentSendController = PaymentSendController()
        paymentSendController.delegate = self

        Navigator.presentModally(paymentSendController)
    }

    func didTapRateUser() {
        presentUserRatingPrompt(contact: contact)
    }

    private func presentUserRatingPrompt(contact: TokenUser) {
        let rateUserController = RateUserController(user: contact)
        rateUserController.delegate = self

        Navigator.presentModally(rateUserController)
    }

    @objc private func displayActions() {
        let actions = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let blockingManager = OWSBlockingManager.shared()
        let address = contact.address

        if contact.isBlocked {
            actions.addAction(UIAlertAction(title: "Unblock", style: .destructive, handler: { _ in
                blockingManager.removeBlockedPhoneNumber(address)
            }))
        } else {
            actions.addAction(UIAlertAction(title: "Block", style: .destructive, handler: { _ in
                blockingManager.addBlockedPhoneNumber(address)
            }))
        }

        actions.addAction(UIAlertAction(title: "Report", style: .destructive, handler: { _ in
            self.idAPIClient.reportUser(address: address) { success, errorMessage in
                print(success)
                print(errorMessage)
            }
        }))

        actions.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        Navigator.presentModally(actions)
    }

    fileprivate func updateReputation() {
        RatingsClient.shared.scores(for: contact.address) { ratingScore in
            self.reputationView.setScore(ratingScore)
        }
    }
}

extension ContactController: ActivityIndicating {
    var activityIndicator: UIActivityIndicatorView {
        return activityView
    }
}

extension ContactController: RateUserControllerDelegate {
    func didRate(_ user: TokenUser, rating: Int, review: String) {
        dismiss(animated: true) {
            RatingsClient.shared.submit(userId: user.address, rating: rating, review: review) {
                self.updateReputation()
            }
        }
    }
}

extension ContactController: PaymentSendControllerDelegate {
    func paymentSendControllerDidFinish(valueInWei: NSDecimalNumber?) {
        defer {
            self.dismiss(animated: true)
        }

        guard let value = valueInWei else {
            return
        }

        let etherAPIClient = EthereumAPIClient.shared

        let parameters: [String: Any] = [
            "from": Cereal.shared.paymentAddress,
            "to": self.contact.paymentAddress,
            "value": value.toHexString
        ]

        showActivityIndicator()

        etherAPIClient.createUnsignedTransaction(parameters: parameters) { transaction, error in

            guard let transaction = transaction as String? else {
                self.hideActivityIndicator()
                let alert = UIAlertController.dismissableAlert(title: "Error completing transaction", message: error?.localizedDescription)
                Navigator.presentModally(alert)

                return
            }

            let signedTransaction = "0x\(Cereal.shared.signWithWallet(hex: transaction))"

            etherAPIClient.sendSignedTransaction(originalTransaction: transaction, transactionSignature: signedTransaction) { json, error in

                self.hideActivityIndicator()

                if error != nil {

                    var message = "Something went wrong"
                    if let json = json?.dictionary as [String: Any]?, let jsonMessage = json["message"] as? String {
                        message = jsonMessage
                    }

                    let alert = UIAlertController.dismissableAlert(title: "Error completing transaction", message: message)
                    Navigator.presentModally(alert)
                } else if let json = json?.dictionary {
                    guard let txHash = json["tx_hash"] as? String else { fatalError("Error recovering transaction hash.") }
                    let payment = SofaPayment(txHash: txHash, valueHex: value.toHexString)

                    // send message to thread
                    let thread = ChatsInteractor.getOrCreateThread(for: self.contact.address)
                    let timestamp = NSDate.ows_millisecondsSince1970(for: Date())
                    let outgoingMessage = TSOutgoingMessage(timestamp: timestamp, in: thread, messageBody: payment.content)

                    self.messageSender?.send(outgoingMessage, success: {
                        print("message sent")
                    }, failure: { error in
                        print(error)
                    })
                }
            }
        }
    }
}
