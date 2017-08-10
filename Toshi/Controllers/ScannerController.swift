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
import CameraScanner

class ScannerController: ScannerViewController {

    var isStatusBarHidden = false

    override func viewDidLoad() {
        super.viewDidLoad()

        setupActivityIndicator()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.setNavigationBarHidden(true, animated: true)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        navigationController?.setNavigationBarHidden(false, animated: true)
    }

    fileprivate lazy var activityView: UIActivityIndicatorView = {
        self.defaultActivityIndicator()
    }()

    override var prefersStatusBarHidden: Bool {
        return isStatusBarHidden
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .slide
    }

    override func setupToolbarItems() {
        toolbar.setItems([self.cancelItem], animated: true)
    }

    fileprivate func showErrorAlert() {
        let controller = UIAlertController.dismissableAlert(title: "Something went wrong")
        Navigator.presentModally(controller)
    }
}

extension ScannerController: ActivityIndicating {

    var activityIndicator: UIActivityIndicatorView {
        return activityView
    }
}

extension ScannerController: PaymentPresentable {

    func setStatusBarHidden(_: Bool) {
        isStatusBarHidden = true
        setNeedsStatusBarAppearanceUpdate()
    }

    func paymentFailed(with _: Error?, result _: [String: Any]) {
        startScanning()
        isStatusBarHidden = false
        startScanning()
    }

    func paymentDeclined() {
        isStatusBarHidden = false
        startScanning()
    }

    func paymentApproved(with parameters: [String: Any], userInfo: UserInfo) {
        isStatusBarHidden = false
        guard !userInfo.isLocal else {
            if let tabbarController = self.presentingViewController as? TabBarController, let address = userInfo.address as String? {
                tabbarController.openPaymentMessage(to: address, parameters: parameters)
            }

            return
        }

        showActivityIndicator()

        EthereumAPIClient.shared.createUnsignedTransaction(parameters: parameters) { transaction, error in

            guard let transaction = transaction as String? else {
                self.hideActivityIndicator()
                self.showErrorAlert()
                self.startScanning()

                return
            }

            let signedTransaction = "0x\(Cereal.shared.signWithWallet(hex: transaction))"

            EthereumAPIClient.shared.sendSignedTransaction(originalTransaction: transaction, transactionSignature: signedTransaction) { json, error in

                self.hideActivityIndicator()

                guard let json = json?.dictionary else {
                    self.showErrorAlert()
                    self.startScanning()

                    return
                }

                if error != nil {
                    self.presentPaymentError(error: error, json: json)
                } else {
                    self.presentSuccessAlert { _ in
                        self.startScanning()
                    }
                }
            }
        }
    }
}
