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
import SweetFoundation
import SweetSwift

public extension Array {
    public var any: Element? {
        return self[Int(arc4random_uniform(UInt32(self.count)))] as Element
    }
}

open class FavoritesController: SweetTableController {

    fileprivate lazy var mappings: YapDatabaseViewMappings = {
        let mappings = YapDatabaseViewMappings(groups: [TokenUser.favoritesCollectionKey], view: TokenUser.viewExtensionName)
        mappings.setIsReversed(true, forGroup: TokenUser.favoritesCollectionKey)

        return mappings
    }()

    fileprivate lazy var uiDatabaseConnection: YapDatabaseConnection = {
        let database = Yap.sharedInstance.database
        let dbConnection = database!.newConnection()
        dbConnection.beginLongLivedReadTransaction()

        return dbConnection
    }()

    fileprivate var idAPIClient: IDAPIClient {
        return IDAPIClient.shared
    }

    fileprivate var searchContacts = [TokenUser]() {
        didSet {
            self.showOrHideEmptyState()
        }
    }

    fileprivate lazy var addButton: UIBarButtonItem = {
        let view = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(self.didTapAddButton))

        return view
    }()

    fileprivate lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchResultsUpdater = self
        controller.dimsBackgroundDuringPresentation = false
        controller.hidesNavigationBarDuringPresentation = false

        controller.searchBar.delegate = self
        controller.searchBar.barTintColor = Theme.viewBackgroundColor
        controller.searchBar.tintColor = Theme.tintColor
        controller.searchBar.searchBarStyle = .minimal
        controller.searchBar.backgroundColor = Theme.viewBackgroundColor
        controller.searchBar.placeholder = "Search by username"

        controller.searchBar.layer.borderWidth = 1.0 / UIScreen.main.scale
        controller.searchBar.layer.borderColor = Theme.borderColor.cgColor

        let searchField = controller.searchBar.value(forKey: "searchField") as? UITextField
        searchField?.backgroundColor = Theme.inputFieldBackgroundColor

        return controller
    }()

    fileprivate lazy var emptyStateContainerView: UIView = {
        let view = UIView(withAutoLayout: true)
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    public init() {
        super.init(style: .plain)

        if TokenUser.current != nil {
            setupForCurrentUserNotifications()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(userCreated(_:)), name: .userCreated, object: nil)

        title = "Favorites"
    }

    @objc fileprivate func userCreated(_ notification: Notification) {
        setupForCurrentUserNotifications()
    }

    fileprivate func setupForCurrentUserNotifications() {
        registerTokenContactsDatabaseView()

        uiDatabaseConnection.asyncRead { transaction in
            self.mappings.update(with: transaction)
        }

        registerDatabaseNotifications()
    }

    public required init?(coder _: NSCoder) {
        fatalError("")
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        addSubviewsAndConstraints()

        view.layoutIfNeeded()
        adjustEmptyView()

        tableView.register(ContactCell.self)
        tableView.register(ChatCell.self)

        tableView.dataSource = self
        tableView.delegate = self

        tableView.backgroundColor = Theme.viewBackgroundColor
        tableView.separatorStyle = .none
        tableView.tableHeaderView = searchController.searchBar

        navigationItem.rightBarButtonItem = addButton

        definesPresentationContext = true

        let appearance = UIButton.appearance(whenContainedInInstancesOf: [UISearchBar.self])
        appearance.setTitleColor(Theme.greyTextColor, for: .normal)

        displayContacts()

        if let address = UserDefaults.standard.string(forKey: FavoritesNavigationController.selectedContactKey) {
            // This doesn't restore a contact if they are not our contact, but a search result
            DispatchQueue.main.asyncAfter(seconds: 0.0) {
                guard let contact = self.contact(with: address) else { return }

                let appController = ContactController(contact: contact)
                self.navigationController?.pushViewController(appController, animated: false)
            }
        }
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        tableView.reloadData()
        showOrHideEmptyState()
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        for view in searchController.searchBar.subviews {
            view.clipsToBounds = false
        }
        searchController.searchBar.superview?.clipsToBounds = false
    }

    fileprivate func addSubviewsAndConstraints() {
        view.addSubview(emptyStateContainerView)
        let topSpace: CGFloat = (navigationController?.navigationBar.frame.height ?? 0.0) + searchController.searchBar.frame.height + UIApplication.shared.statusBarFrame.height
        emptyStateContainerView.set(height: view.frame.height - topSpace)
        emptyStateContainerView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        emptyStateContainerView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        emptyStateContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    }

    fileprivate func showOrHideEmptyState() {
        var shouldHideEmptyState = false

        let hasFavourites = mappings.numberOfItems(inSection: 0) > 0

        if searchController.isActive {
            shouldHideEmptyState = !searchContacts.isEmpty || hasFavourites
        } else {
            shouldHideEmptyState = hasFavourites
        }

        makeEmptyView(hidden: shouldHideEmptyState)
    }

    fileprivate func contactSorting() -> YapDatabaseViewSorting {
        let viewSorting = YapDatabaseViewSorting.withObjectBlock { (_, _, _, _, object1, _, _, object2) -> ComparisonResult in
            if let data1 = object1 as? Data, let data2 = object2 as? Data,
                let contact1 = TokenUser.user(with: data1) as TokenUser?,
                let contact2 = TokenUser.user(with: data2) as TokenUser? {

                return contact1.username.compare(contact2.username)
            }

            return .orderedAscending
        }

        return viewSorting
    }

    @discardableResult
    fileprivate func registerTokenContactsDatabaseView() -> Bool {
        // Check if it's already registered.
        guard Yap.sharedInstance.database!.registeredExtension(TokenUser.viewExtensionName) == nil else { return true }

        let viewGrouping = YapDatabaseViewGrouping.withObjectBlock { (_, _, _, object) -> String? in
            if (object as? Data) != nil {
                return TokenUser.favoritesCollectionKey
            }

            return nil
        }

        let viewSorting = contactSorting()

        let options = YapDatabaseViewOptions()
        options.isPersistent = false
        options.allowedCollections = YapWhitelistBlacklist(whitelist: Set([TokenUser.favoritesCollectionKey]))

        let databaseView = YapDatabaseView(grouping: viewGrouping, sorting: viewSorting, versionTag: "1", options: options)

        return Yap.sharedInstance.database!.register(databaseView, withName: TokenUser.viewExtensionName)
    }

    fileprivate func displayContacts() {
        searchController.isActive = false
        tableView.reloadData()
        showOrHideEmptyState()
    }

    fileprivate func registerDatabaseNotifications() {
        let notificationController = NotificationCenter.default
        notificationController.addObserver(self, selector: #selector(yapDatabaseDidChange(notification:)), name: .YapDatabaseModified, object: nil)
    }

    @objc
    fileprivate func yapDatabaseDidChange(notification _: NSNotification) {
        defer {
            self.showOrHideEmptyState()
        }

        let notifications = uiDatabaseConnection.beginLongLivedReadTransaction()

        // If changes do not affect current view, update and return without updating collection view
        let viewConnection = uiDatabaseConnection.ext(TSThreadDatabaseViewExtensionName) as! YapDatabaseViewConnection
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

        guard !searchController.isActive else { return }

        tableView.beginUpdates()

        for rowChange in messageRowChanges as! [YapDatabaseViewRowChange] {

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
                tableView.reloadRows(at: [rowChange.indexPath], with: .middle)
            }
        }

        tableView.endUpdates()
    }

    fileprivate func updateContactIfNeeded(at indexPath: IndexPath) {
        guard let contact = self.contact(at: indexPath) as TokenUser?,
            let address = contact.address as String? else { return }

        print("Updating contact infor for address: \(address).")

        self.idAPIClient.findContact(name: address) { contact in
            if let contact = contact {
                print("Added contact info for \(contact.username)")

                self.tableView.beginUpdates()
                self.tableView.reloadRows(at: [indexPath], with: .automatic)
                self.tableView.endUpdates()
            }
        }
    }

    fileprivate func contact(at indexPath: IndexPath) -> TokenUser? {
        var contact: TokenUser?

        self.uiDatabaseConnection.read { transaction in
            guard let dbExtension: YapDatabaseViewTransaction = transaction.extension(TokenUser.viewExtensionName) as? YapDatabaseViewTransaction else { return }

            guard let data = dbExtension.object(at: indexPath, with: self.mappings) as? Data else { return }

            contact = TokenUser.user(with: data, shouldUpdate: false)
        }

        return contact
    }

    fileprivate func contact(with address: String) -> TokenUser? {
        var contact: TokenUser?

        self.uiDatabaseConnection.read { transaction in
            if let data = transaction.object(forKey: address, inCollection: TokenUser.favoritesCollectionKey) as? Data {
                contact = TokenUser.user(with: data)
            }
        }

        return contact
    }

    @objc
    fileprivate func didTapAddButton() {
        let addContactSheet = UIAlertController(title: "Add to favorites on Token", message: nil, preferredStyle: .actionSheet)

        addContactSheet.addAction(UIAlertAction(title: "Add by username", style: .default, handler: { _ in
            self.searchController.searchBar.becomeFirstResponder()
        }))

        addContactSheet.addAction(UIAlertAction(title: "Invite friends", style: .default, handler: { _ in
            let shareController = UIActivityViewController(activityItems: ["Get Token, available for iOS and Android! (https://tokenbrowser.com)"], applicationActivities: [])

            Navigator.presentModally(shareController)
        }))

        addContactSheet.addAction(UIAlertAction(title: "Scan code", style: .default, handler: { _ in
            guard let tabBarController = self.tabBarController as? TabBarController else { return }
            tabBarController.switch(to: .scanner)
        }))

        addContactSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        addContactSheet.view.tintColor = Theme.tintColor
        self.present(addContactSheet, animated: true) {
            // Due to a UIKit "bug", tint colour need be reset here.
            addContactSheet.view.tintColor = Theme.tintColor
        }
    }
}

extension FavoritesController: Emptiable {
    var buttonPressed: Selector {
        return #selector(buttonPressed(sender:))
    }

    func contentCenterVerticalOffset() -> CGFloat {
        let topSpace: CGFloat = self.navigationController?.navigationBar.frame.height ?? 0.0
        return -topSpace
    }

    func emptyStateTitle() -> String {
        return "No favorites yet"
    }

    func emptyStateDescription() -> String {
        return "Your favorites will be listed here. You\ncan invite friends to join Token."
    }

    func emptyStateButtonTitle() -> String {
        return "Invite friends"
    }

    func sourceView() -> UIView {
        return self.emptyStateContainerView
    }

    func isScrollable() -> Bool {
        return true
    }

    func buttonPressed(sender _: AnyObject) {
        let shareController = UIActivityViewController(activityItems: ["Get Token, available for iOS and Android! (https://tokenbrowser.com)"], applicationActivities: [])

        Navigator.presentModally(shareController)
    }
}

extension FavoritesController: UITableViewDataSource {

    open func numberOfSections(in _: UITableView) -> Int {
        if self.searchController.isActive {
            return 1
        }

        return Int(self.mappings.numberOfSections())
    }

    open func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        if self.searchController.isActive {
            return self.searchContacts.count
        }

        return Int(self.mappings.numberOfItems(inSection: UInt(section)))
    }

    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeue(ContactCell.self, for: indexPath)

        if self.searchController.isActive {
            cell.contact = self.searchContacts[indexPath.row]
        } else {
            cell.contact = self.contact(at: indexPath)
        }

        return cell
    }
}

extension FavoritesController: UITableViewDelegate {

    public func tableView(_: UITableView, estimatedHeightForRowAt _: IndexPath) -> CGFloat {
        return UITableViewAutomaticDimension
    }

    public func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.searchController.searchBar.resignFirstResponder()

        if let contact = self.searchController.isActive ? self.searchContacts[indexPath.row] : self.contact(at: indexPath) as TokenUser? {

            let contactController = ContactController(contact: contact)
            self.navigationController?.pushViewController(contactController, animated: true)

            UserDefaults.standard.setValue(contact.address, forKey: FavoritesNavigationController.selectedContactKey)
        }
    }
}

extension FavoritesController: UISearchBarDelegate {

    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = nil
        self.displayContacts()
    }
}

extension FavoritesController: UISearchResultsUpdating {

    public func updateSearchResults(for searchController: UISearchController) {
        guard let text = searchController.searchBar.text else { return }

        if text.isEmpty {
            self.searchContacts = []
            self.tableView.reloadData()
        } else {
            self.idAPIClient.searchContacts(name: text) { contacts in
                self.searchContacts = contacts
                self.tableView.reloadData()
            }
        }
    }
}
