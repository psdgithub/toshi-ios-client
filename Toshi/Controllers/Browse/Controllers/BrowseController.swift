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

import SweetFoundation
import UIKit
import SweetUIKit

enum BrowseContentSection {
    case topRatedApps
    case featuredApps
    case topRatedPublicUsers
    case latestPublicUsers

    var title: String {
        switch self {
        case .topRatedApps:
            return Localized("browse-top-rated-apps")
        case .featuredApps:
            return Localized("browse-featured-apps")
        case .topRatedPublicUsers:
            return Localized("browse-top-rated-public-users")
        case .latestPublicUsers:
            return Localized("browse-latest-public-users")
        }
    }
}

class BrowseController: SearchableCollectionController {

    fileprivate var contentSections: [BrowseContentSection] = [.topRatedApps, .featuredApps, .topRatedPublicUsers, .latestPublicUsers]

    fileprivate var items: [[TokenUser]] = [[], [], [], []]

    fileprivate lazy var searchResultView: BrowseSearchResultView = {
        let view = BrowseSearchResultView()
        view.alpha = 0

        return view
    }()

    fileprivate lazy var openURLButton: OpenURLButton = {
        let view = OpenURLButton(withAutoLayout: true)
        view.addTarget(self, action: #selector(self.didTapOpenURLButton), for: .touchUpInside)
        view.isHidden = true

        return view
    }()

    fileprivate lazy var openButtonAttributes: [String: Any] = {
        let paragraph = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraph.alignment = .left

        return [NSForegroundColorAttributeName: Theme.tintColor, NSFontAttributeName: Theme.regular(size: 14)]
    }()

    fileprivate var openURLButtonTopAnchor: NSLayoutConstraint!

    private lazy var layout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.itemSize = CGSize(width: UIScreen.main.bounds.width, height: 230)
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0

        return layout
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = Localized("browse-navigation-title")

        collectionView.showsVerticalScrollIndicator = true
        collectionView.alwaysBounceVertical = true
        collectionView.backgroundColor = Theme.viewBackgroundColor
        collectionView.dataSource = self
        collectionView.contentInset = UIEdgeInsets(top: searchBar.frame.height, left: 0, bottom: 0, right: 0)
        collectionView.setCollectionViewLayout(layout, animated: false)
        collectionView.register(BrowseCell.self)

        searchBar.delegate = self
        searchBar.barTintColor = Theme.viewBackgroundColor
        searchBar.tintColor = Theme.tintColor
        searchBar.placeholder = Localized("browse-search-placeholder")

        let searchField = searchBar.value(forKey: "searchField") as? UITextField
        searchField?.backgroundColor = Theme.inputFieldBackgroundColor

        addSubviewsAndConstraints()

        loadItems()
    }

    private func addSubviewsAndConstraints() {
        view.addSubview(searchResultView)
        view.addSubview(openURLButton)

        searchResultView.top(to: view, offset: 64)
        searchResultView.left(to: view)
        searchResultView.bottom(to: view)
        searchResultView.right(to: view)

        openURLButton.height(44)
        openURLButton.left(to: view).isActive = true
        openURLButton.right(to: view).isActive = true
        openURLButtonTopAnchor = openURLButton.top(to: collectionView)
        openURLButtonTopAnchor.constant = -searchBar.frame.maxY + 64
        openURLButtonTopAnchor.isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        collectionView.reloadData()
        collectionView.collectionViewLayout.invalidateLayout()

        if let indexPathForSelectedRow = searchResultView.indexPathForSelectedRow {
            searchResultView.deselectRow(at: indexPathForSelectedRow, animated: true)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        searchBar.resignFirstResponder()
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView == collectionView else { return }

        super.scrollViewDidScroll(scrollView)

        /* Adjust scroll indicator insets while scrolling to keep
         the indicator below the search bar. */
        collectionView.scrollIndicatorInsets.top = max(0, scrollView.contentOffset.y * -1)
    }

    private func loadItems() {

        AppsAPIClient.shared.getTopRatedApps { apps, error in
            if let error = error {
                let alertController = UIAlertController.errorAlert(error as NSError)
                Navigator.presentModally(alertController)
            }

            self.items[0] = apps ?? []
            self.collectionView.reloadItems(at: [IndexPath(item: 0, section: 0)])
            self.collectionView.collectionViewLayout.invalidateLayout()
        }

        AppsAPIClient.shared.getFeaturedApps { apps, error in
            if let error = error {
                let alertController = UIAlertController.errorAlert(error as NSError)
                Navigator.presentModally(alertController)
            }

            self.items[1] = apps ?? []
            self.collectionView.reloadItems(at: [IndexPath(item: 1, section: 0)])
            self.collectionView.collectionViewLayout.invalidateLayout()
        }

        IDAPIClient.shared.getTopRatedPublicUsers { users, error in

            if let error = error {
                let alertController = UIAlertController.errorAlert(error as NSError)
                Navigator.presentModally(alertController)
            }

            self.items[2] = users ?? []
            self.collectionView.reloadItems(at: [IndexPath(item: 2, section: 0)])
            self.collectionView.collectionViewLayout.invalidateLayout()
        }

        IDAPIClient.shared.getLatestPublicUsers { users, error in

            if let error = error {
                let alertController = UIAlertController.errorAlert(error as NSError)
                Navigator.presentModally(alertController)
            }

            self.items[3] = users ?? []
            self.collectionView.reloadItems(at: [IndexPath(item: 3, section: 0)])
            self.collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    @objc
    fileprivate func reload(searchText: String) {

        if searchText.isURL {
            let title = NSAttributedString(string: searchText, attributes: openButtonAttributes)
            openURLButton.setAttributedTitle(title)

            searchResultView.searchResults = []

            showOpenURLButton()
        } else {
            hideOpenURLButtonIfNeeded()

            AppsAPIClient.shared.search(searchText) { apps, error in
                if let error = error {
                    let alertController = UIAlertController.errorAlert(error as NSError)
                    Navigator.presentModally(alertController)
                }

                if searchText == self.searchBar.text {
                    self.searchResultView.searchResults = apps
                }
            }
        }
    }

    fileprivate func showOpenURLButton() {
        openURLButton.isHidden = false
        openURLButtonTopAnchor.constant = searchBar.frame.minY - 20 + 64
        UIView.animate(withDuration: 0.25) {
            self.collectionView.layoutIfNeeded()
        }
    }

    fileprivate func hideOpenURLButtonIfNeeded() {
        guard openURLButtonTopAnchor.constant == 64 else { return }

        openURLButton.isHidden = true
        openURLButtonTopAnchor.constant = -searchBar.frame.maxY + 64
        UIView.animate(withDuration: 0.25) {
            self.collectionView.layoutIfNeeded()
            self.openURLButton.setAttributedTitle(nil)
        }
    }

    @objc
    fileprivate func didTapOpenURLButton() {
        guard let string = searchController.searchBar.text, let url = URL(string: string) else { return }

        let sofaController = SOFAWebController()

        sofaController.load(url: url)
        navigationController?.pushViewController(sofaController, animated: true)
    }
}

extension BrowseController: UISearchBarDelegate {

    func searchBar(_: UISearchBar, textDidChange searchText: String) {

        searchResultView.alpha = 1

        if searchText.isEmpty {
            searchResultView.searchResults = []
            hideOpenURLButtonIfNeeded()
        }

        reload(searchText: searchText)
    }

    func searchBarCancelButtonClicked(_: UISearchBar) {
        searchResultView.alpha = 0
        searchResultView.searchResults = []
        hideOpenURLButtonIfNeeded()
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        if let collectionView = collectionView as? SectionedCollectionView {
            let cell = collectionView.dequeue(BrowseAppCell.self, for: indexPath)

            if let section = items.element(at: collectionView.section), let item = section.element(at: indexPath.item) {
                if !item.name.isEmpty {
                    cell.nameLabel.text = item.name
                } else {
                    cell.nameLabel.text = item.isApp ? item.category : item.username
                }

                if let url = URL(string: item.avatarPath) {
                    cell.avatarImageView.setImage(from: AsyncImageURL(url: url))
                }

                if let averageRating = item.averageRating {
                    cell.ratingView.set(rating: averageRating)
                }
            }

            return cell
        }

        let contentSection = contentSections[indexPath.item]

        let cell = collectionView.dequeue(BrowseCell.self, for: indexPath)
        cell.collectionView.dataSource = self
        cell.collectionView.reloadData()
        cell.collectionView.collectionViewLayout.invalidateLayout()
        cell.collectionView.section = indexPath.item
        cell.contentSection = contentSection
        cell.selectionDelegate = self
        cell.divider.isHidden = contentSection == .latestPublicUsers

        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection _: Int) -> Int {

        if let collectionView = collectionView as? SectionedCollectionView {
            return items[collectionView.section].count
        }

        return items.count
    }
}

extension BrowseController: BrowseCellSelectionDelegate {

    func seeAll(for contentSection: BrowseContentSection) {
        let controller = BrowseAllController(contentSection)
        controller.title = contentSection.title
        Navigator.push(controller)
    }

    func didSelectItem(at indexPath: IndexPath, collectionView: SectionedCollectionView) {

        if let section = items.element(at: collectionView.section), let item = section.element(at: indexPath.item) {
            Navigator.push(ContactController(contact: item))
        }
    }
}
