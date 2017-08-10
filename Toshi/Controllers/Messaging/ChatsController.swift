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
import SweetFoundation
import SweetUIKit

public extension NSNotification.Name {
    public static let ChatDatabaseCreated = NSNotification.Name(rawValue: "ChatDatabaseCreated")
}

/// Displays current conversations.
open class ChatsController: SweetTableController {

    lazy var mappings: YapDatabaseViewMappings = {
        let mappings = YapDatabaseViewMappings(groups: [TSInboxGroup], view: TSThreadDatabaseViewExtensionName)
        mappings.setIsReversed(true, forGroup: TSInboxGroup)

        return mappings
    }()

    lazy var uiDatabaseConnection: YapDatabaseConnection = {
        let database = TSStorageManager.shared().database()!
        let dbConnection = database.newConnection()
        dbConnection.beginLongLivedReadTransaction()

        return dbConnection
    }()

    fileprivate var chatAPIClient: ChatAPIClient {
        return ChatAPIClient.shared
    }

    fileprivate var idAPIClient: IDAPIClient {
        return IDAPIClient.shared
    }

    public init() {
        super.init()

        title = "Recent"

        loadViewIfNeeded()

        if TokenUser.current != nil {
            self.loadMessages()
        } else {
            NotificationCenter.default.addObserver(self, selector: #selector(chatDBCreated(_:)), name: .ChatDatabaseCreated, object: nil)

            showEmptyStateIfNeeded()
        }
    }

    fileprivate func loadMessages() {
        uiDatabaseConnection.asyncRead { [weak self] transaction in
            self?.mappings.update(with: transaction)

            DispatchQueue.main.async {
                self?.showEmptyStateIfNeeded()
            }
        }

        registerNotifications()
    }

    public required init?(coder _: NSCoder) {
        fatalError()
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        addSubviewsAndConstraints()

        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ChatCell.self)
        tableView.showsVerticalScrollIndicator = true
        tableView.alwaysBounceVertical = true
        NotificationCenter.default.post(name: IDAPIClient.updateContactsNotification, object: nil, userInfo: nil)

        adjustEmptyView()
    }

    @objc fileprivate func chatDBCreated(_ notification: Notification) {
        loadMessages()
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tabBarController?.tabBar.isHidden = false
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    fileprivate lazy var emptyStateContainerView: UIView = {
        let view = UIView(withAutoLayout: true)
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    fileprivate func addSubviewsAndConstraints() {
        view.addSubview(emptyStateContainerView)
        let topSpace: CGFloat = (navigationController?.navigationBar.frame.height ?? 0.0)
        emptyStateContainerView.set(height: view.frame.height - topSpace)
        emptyStateContainerView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        emptyStateContainerView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        emptyStateContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        view.layoutIfNeeded()
    }

    func registerNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(yapDatabaseDidChange(notification:)), name: .YapDatabaseModified, object: nil)
    }

    func yapDatabaseDidChange(notification _: NSNotification) {
        let notifications = uiDatabaseConnection.beginLongLivedReadTransaction()

        // If changes do not affect current view, update and return without updating collection view
        guard let viewConnection = self.uiDatabaseConnection.ext(TSThreadDatabaseViewExtensionName) as? YapDatabaseViewConnection else { return }

        let hasChangesForCurrentView = viewConnection.hasChanges(for: notifications)
        if !hasChangesForCurrentView {
            uiDatabaseConnection.read { transaction in
                self.mappings.update(with: transaction)
            }

            return
        }

        var messageRowChanges = NSArray()
        var sectionChanges = NSArray()

        viewConnection.getSectionChanges(&sectionChanges, rowChanges: &messageRowChanges, for: notifications, with: mappings)

        if sectionChanges.count == 0 && messageRowChanges.count == 0 {
            return
        }

        let rowChanges = messageRowChanges as! [YapDatabaseViewRowChange]

        if let insertedRow = rowChanges.first(where: { $0.type == .insert }) {
            if let thread = self.thread(at: insertedRow.newIndexPath) as TSThread?, let contactIdentfier = thread.contactIdentifier() as String? {
                IDAPIClient.shared.updateContact(with: contactIdentfier)
            }
        }

        // No need to animate the tableview if not being presented.
        // Avoids an issue where tableview will actually cause a crash on update
        // during a chat update.
        if navigationController?.topViewController == self && tabBarController?.selectedViewController == navigationController {
            tableView.beginUpdates()

            for rowChange in rowChanges {
                switch rowChange.type {
                case .delete:
                    tableView.deleteRows(at: [rowChange.indexPath], with: .left)
                case .insert:
                    updateContactIfNeeded(at: rowChange.newIndexPath)
                    tableView.insertRows(at: [rowChange.newIndexPath], with: .right)
                case .move:
                    tableView.deleteRows(at: [rowChange.indexPath], with: .left)
                    tableView.insertRows(at: [rowChange.newIndexPath], with: .right)
                case .update:
                    tableView.reloadRows(at: [rowChange.indexPath], with: .automatic)
                }
            }

            tableView.endUpdates()
        } else {
            tableView.reloadData()
        }

        showEmptyStateIfNeeded()
    }

    private func showEmptyStateIfNeeded() {
        let shouldHideEmptyState = mappings.numberOfItems(inSection: 0) > 0

        makeEmptyView(hidden: shouldHideEmptyState)
    }

    func updateContactIfNeeded(at indexPath: IndexPath) {
        if let thread = self.thread(at: indexPath), let address = thread.contactIdentifier() as String? {
            print("Updating contact infor for address: \(address).")

            idAPIClient.retrieveContact(username: address) { contact in
                if let contact = contact {
                    print("Updated contact info for \(contact.username)")
                }
            }
        }
    }

    func thread(at indexPath: IndexPath) -> TSThread? {
        var thread: TSThread?

        uiDatabaseConnection.read { transaction in
            guard let dbExtension = transaction.extension(TSThreadDatabaseViewExtensionName) as? YapDatabaseViewTransaction else { return }
            guard let object = dbExtension.object(at: indexPath, with: self.mappings) as? TSThread else { return }

            thread = object
        }

        return thread
    }

    func thread(withAddress address: String) -> TSThread? {
        var thread: TSThread?

        uiDatabaseConnection.read { transaction in
            transaction.enumerateRows(inCollection: TSThread.collection()) { _, object, _, stop in
                if let possibleThread = object as? TSThread {
                    if possibleThread.contactIdentifier() == address {
                        thread = possibleThread
                        stop.pointee = true
                    }
                }
            }
        }

        return thread
    }

    func thread(withIdentifier identifier: String) -> TSThread? {
        var thread: TSThread?

        uiDatabaseConnection.read { transaction in
            transaction.enumerateRows(inCollection: TSThread.collection()) { _, object, _, stop in
                if let possibleThread = object as? TSThread {
                    if possibleThread.uniqueId == identifier {
                        thread = possibleThread
                        stop.pointee = true
                    }
                }
            }
        }

        return thread
    }
}

extension ChatsController: Emptiable {

    var buttonPressed: Selector {
        return #selector(buttonPressed(sender:))
    }

    func emptyStateTitle() -> String {
        return "No chats yet"
    }

    func emptyStateDescription() -> String {
        return "Once you start a new conversation,\nyou'll see it here."
    }

    func emptyStateButtonTitle() -> String {
        return "Invite friends"
    }

    func sourceView() -> UIView {
        return emptyStateContainerView
    }

    func isScrollable() -> Bool {
        return true
    }

    func buttonPressed(sender _: AnyObject) {
        let shareController = UIActivityViewController(activityItems: ["Get Toshi, available for iOS and Android! (https://toshi.org)"], applicationActivities: [])

        Navigator.presentModally(shareController)
    }
}

extension ChatsController: UITableViewDelegate {

    open func tableView(_: UITableView, heightForRowAt _: IndexPath) -> CGFloat {
        return 82
    }

    open func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let thread = self.thread(at: indexPath) as TSThread? {
            let chatController = ChatController(thread: thread)
            navigationController?.pushViewController(chatController, animated: true)
        }
    }

    public func tableView(_: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        let action = UITableViewRowAction(style: .destructive, title: "Delete") { _, indexPath in
            if let thread = self.thread(at: indexPath) as TSThread? {

                TSStorageManager.shared().dbConnection?.asyncReadWrite { transaction in
                    thread.remove(with: transaction)
                }
            }
        }

        return [action]
    }
}

extension ChatsController: UITableViewDataSource {

    open func numberOfSections(in _: UITableView) -> Int {
        return Int(mappings.numberOfSections())
    }

    open func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Int(mappings.numberOfItems(inSection: UInt(section)))
    }

    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeue(ChatCell.self, for: indexPath)
        let thread = self.thread(at: indexPath)

        // TODO: deal with last message from thread. It should be last visible message.
        cell.thread = thread

        return cell
    }
}
