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

public class Navigator: NSObject {

    public static var appDelegate: AppDelegate? {
        return UIApplication.shared.delegate as? AppDelegate
    }

    public static var window: UIWindow? {
        return appDelegate?.window
    }

    public static var rootViewController: UIViewController? {
        return window?.rootViewController
    }

    public static var tabbarController: TabBarController? {
        return window?.rootViewController as? TabBarController
    }

    public static var topViewController: UIViewController? {
        var topViewController = topNonModalViewController

        while topViewController?.presentedViewController != nil {
            topViewController = topViewController?.presentedViewController
        }

        return topViewController
    }

    public static var topNonModalViewController: UIViewController? {
        return tabbarController?.currentNavigationController?.topViewController
    }

    public static func push(_ viewController: UIViewController, from fromController: UIViewController? = nil, animated: Bool = true) {
        guard viewController.presentingViewController == nil else { return }

        if fromController?.navigationController != nil {
            fromController?.navigationController?.pushViewController(viewController, animated: animated)
        } else {
            tabbarController?.currentNavigationController?.pushViewController(viewController, animated: animated)
        }
    }

    public static func present(_ viewController: UIViewController, from parentViewController: UIViewController?, animated: Bool, completion: (() -> Void)? = nil) {
        guard viewController.presentingViewController == nil else { return }

        if parentViewController?.presentedViewController != nil {
            parentViewController?.presentedViewController?.dismiss(animated: animated, completion: completion)
        }

        parentViewController?.present(viewController, animated: true, completion: nil)
    }

    public static func presentAddressChangeAlertIfNeeded() {
        guard UserDefaults.standard.bool(forKey: AddressChangeAlertShown) == false else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let alertController = AddressChangeAlertController()
            alertController.modalPresentationStyle = .custom
            alertController.transitioningDelegate = alertController

            self.presentModally(alertController)

            UserDefaults.standard.set(true, forKey: AddressChangeAlertShown)
            UserDefaults.standard.synchronize()
        }
    }

    public static func presentModally(_ controller: UIViewController) {
        present(controller, from: topViewController, animated: true)
    }

    // Navigation assumes the following structure:
    // TabBar controller contains a messages controller. Messages controller lists chats, and pushes threads.
    public static func navigate(to threadIdentifier: String, animated: Bool) {
        // make sure we don't do UI stuff in a background thread
        DispatchQueue.main.async {
            // get tab controller
            guard let tabController = UIApplication.shared.delegate?.window??.rootViewController as? TabBarController else { return }

            if tabController.presentedViewController != nil {
                tabController.dismiss(animated: animated)
            }

            _ = tabController.messagingController.popToRootViewController(animated: animated)
            tabController.messagingController.openThread(withThreadIdentifier: threadIdentifier, animated: animated)
            tabController.switch(to: .messaging)
        }
    }

    public static func openThread(_ thread: TSThread, animated: Bool) {
        guard let tabController = UIApplication.shared.delegate?.window??.rootViewController as? TabBarController else { return }

        if tabController.presentedViewController != nil {
            tabController.dismiss(animated: animated)
        }

        _ = tabController.messagingController.popToRootViewController(animated: animated)
        tabController.messagingController.openThread(thread, animated: true)
        tabController.switch(to: .messaging)
    }
}
