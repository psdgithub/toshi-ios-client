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

protocol PaymentRequestControllerDelegate: class {
    func paymentRequestControllerDidFinish(valueInWei: NSDecimalNumber?)
}

class PaymentRequestController: PaymentController {
    
    weak var delegate: PaymentRequestControllerDelegate?

    lazy var continueBarButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(sendRequest))
    lazy var cancelBarButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelRequest))
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Localized("payment_request")
        
        navigationItem.leftBarButtonItem = cancelBarButton
        navigationItem.rightBarButtonItem = continueBarButton
    }

    func cancelRequest() {
        delegate?.paymentRequestControllerDidFinish(valueInWei: nil)
    }

    func sendRequest() {
        delegate?.paymentRequestControllerDidFinish(valueInWei: valueInWei)
    }
}
