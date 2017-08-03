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

public class ChatsNavigationController: UINavigationController {

    let selectedThreadAddressKey = "Restoration::SelectedThread"

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }

    public override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
    }

    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        tabBarItem = UITabBarItem(title: "Recent", image: #imageLiteral(resourceName: "chats"), tag: 0)
        tabBarItem.selectedImage = #imageLiteral(resourceName: "chats-selected")
        tabBarItem.titlePositionAdjustment.vertical = TabBarItemTitleOffset
    }

    lazy var backgroundBlur: BlurView = {
        let view = BlurView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false

        return view
    }()

    public required init?(coder _: NSCoder) {
        fatalError("")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationBar.barStyle = .default
        navigationBar.setBackgroundImage(UIImage(), for: .any, barMetrics: .default)

        navigationBar.insertSubview(backgroundBlur, at: 0)
        backgroundBlur.edges(to: navigationBar, insets: UIEdgeInsets(top: -20, left: 0, bottom: 0, right: 0))
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        navigationBar.sendSubview(toBack: backgroundBlur)
    }

    public func openThread(withAddress address: String, completion: ((Any?) -> Void)? = nil) {
        _ = popToRootViewController(animated: false)
        guard let chatsController = self.viewControllers.first as? ChatsController else { return }

        if let thread = chatsController.thread(withAddress: address) as TSThread? {
            let messagesController = ChatController(thread: thread)
            pushViewController(messagesController, animated: false)

            completion?(messagesController)
        } else {
            completion?(nil)
        }
    }

    public func openThread(withThreadIdentifier identifier: String, animated: Bool) {
        _ = self.popToRootViewController(animated: animated)
        guard let chatsController = self.viewControllers.first as? ChatsController else { return }
        guard let thread = chatsController.thread(withIdentifier: identifier) else { return }

        let messagesController = ChatController(thread: thread)
        self.pushViewController(messagesController, animated: animated)
    }

    public func openThread(_ thread: TSThread, animated: Bool) {
        let messagesController = ChatController(thread: thread)
        self.pushViewController(messagesController, animated: animated)
    }

    public override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        super.pushViewController(viewController, animated: animated)

        if let viewController = viewController as? ChatController {
            UserDefaults.standard.setValue(viewController.thread.contactIdentifier(), forKey: selectedThreadAddressKey)
        }
    }

    public override func popViewController(animated: Bool) -> UIViewController? {
        UserDefaults.standard.removeObject(forKey: selectedThreadAddressKey)

        return super.popViewController(animated: animated)
    }

    public override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        UserDefaults.standard.removeObject(forKey: selectedThreadAddressKey)

        return super.popToRootViewController(animated: animated)
    }

    public override func popToViewController(_ viewController: UIViewController, animated: Bool) -> [UIViewController]? {
        UserDefaults.standard.removeObject(forKey: selectedThreadAddressKey)

        return super.popToViewController(viewController, animated: animated)
    }
}
