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

protocol PaymentSendControllerDelegate: class {
    func paymentSendControllerCanceled()
    func paymentSendControllerFinished(with valueInWei: NSDecimalNumber?, for controller: PaymentSendController)
}

class PaymentSendController: PaymentController {
    
    weak var delegate: PaymentSendControllerDelegate?
    
    lazy var continueBarButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(send))
    lazy var cancelBarButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))

    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Localized("payment_send")
        
        navigationItem.leftBarButtonItem = cancelBarButton
        navigationItem.rightBarButtonItem = continueBarButton
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationItem.backBarButtonItem = UIBarButtonItem.back
    }

    func cancel() {
        delegate?.paymentSendControllerCanceled()
    }

    func send() {
        delegate?.paymentSendControllerFinished(with: valueInWei, for: self)
    }
}
