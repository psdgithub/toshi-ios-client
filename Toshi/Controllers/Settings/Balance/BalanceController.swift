import Foundation
import UIKit
import TinyConstraints

class BalanceController: UIViewController {

    var balance: NSDecimalNumber? {
        didSet {
            tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .fade)
        }
    }

    private lazy var tableView: UITableView = {
        let view = UITableView(frame: .zero, style: .grouped)
        view.backgroundColor = nil
        view.dataSource = self
        view.delegate = self
        view.separatorStyle = .singleLine

        view.register(UITableViewCell.self, forCellReuseIdentifier: self.reuseIdentifier)

        return view
    }()

    fileprivate let reuseIdentifier = "BalanceControllerCell"

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.settingsBackgroundColor

        title = Localized("balance-navigation-title")

        view.addSubview(tableView)
        tableView.edges(to: view)

        NotificationCenter.default.addObserver(self, selector: #selector(handleBalanceUpdate(notification:)), name: .ethereumBalanceUpdateNotification, object: nil)
        fetchAndUpdateBalance()
    }

    @objc private func handleBalanceUpdate(notification: Notification) {
        guard notification.name == .ethereumBalanceUpdateNotification, let balance = notification.object as? NSDecimalNumber else { return }
        self.balance = balance
    }

    fileprivate func fetchAndUpdateBalance() {

        EthereumAPIClient.shared.getBalance(address: Cereal.shared.paymentAddress) { balance, error in
            if let error = error {
                Navigator.presentModally(UIAlertController.errorAlert(error as NSError))
            } else {
                self.balance = balance
            }
        }
    }
}

extension BalanceController: UITableViewDelegate {

    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {

        if indexPath.row == 1 {
            
            let paymentSendController = PaymentSendController()
            paymentSendController.delegate = self
            
            let navigationController = PaymentNavigationController(rootViewController: paymentSendController)
            Navigator.presentModally(navigationController)
            
        } else if indexPath.row == 2 {
            guard let current = TokenUser.current else { return }
            let controller = AddMoneyController(for: current.displayUsername, name: current.name)
            self.navigationController?.pushViewController(controller, animated: true)
        }
    }
}

extension BalanceController: UITableViewDataSource {

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier, for: indexPath)
        cell.selectionStyle = .none

        switch indexPath.row {
        case 0:
            if let balance = balance {
                cell.textLabel?.attributedText = EthereumConverter.balanceSparseAttributedString(forWei: balance, exchangeRate: EthereumAPIClient.shared.exchangeRate, width: UIScreen.main.bounds.width - 40)
            }
        case 1:
            cell.textLabel?.text = Localized("balance-action-send")
            cell.textLabel?.textColor = Theme.tintColor
            cell.textLabel?.font = Theme.regular(size: 17)
        case 2:
            cell.textLabel?.text = Localized("balance-action-deposit")
            cell.textLabel?.textColor = Theme.tintColor
            cell.textLabel?.font = Theme.regular(size: 17)
        default:
            break
        }

        return cell
    }
}

extension BalanceController: PaymentSendControllerDelegate {
    
    func paymentSendControllerCanceled() {
        dismiss(animated: true)
    }
    
    func paymentSendControllerFinished(with valueInWei: NSDecimalNumber?, for controller: PaymentSendController) {
        
        guard let valueInWei = valueInWei else { return }
        
        let paymentAddressController = PaymentAddressController(with: valueInWei)
        controller.navigationController?.pushViewController(paymentAddressController, animated: true)
    }
}
