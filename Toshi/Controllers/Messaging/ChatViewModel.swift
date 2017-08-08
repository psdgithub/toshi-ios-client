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

import Foundation

enum DisplayState {
    case hide
    case show
    case hideAndShow
    case doNothing
}

protocol ChatViewModelOutput: ChatInteractorOutput {
    func didReload()
}

final class ChatViewModel {

    fileprivate var output: ChatViewModelOutput

    init(output: ChatViewModelOutput, thread: TSThread) {
        self.output = output
        self.thread = thread

        storageManager = TSStorageManager.shared()

        uiDatabaseConnection.asyncRead { transaction in
            self.mappings.update(with: transaction)
        }

        loadMessages()
        registerNotifications()

        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        contactsManager = appDelegate?.contactsManager
    }

    fileprivate var contactsManager: ContactsManager?

    fileprivate var etherAPIClient: EthereumAPIClient {
        return EthereumAPIClient.shared
    }

    private(set) var thread: TSThread

    private(set) lazy var interactor: ChatsInteractor = {
        ChatsInteractor(output: self.output, thread: self.thread)
    }()

    var contact: TokenUser? {
        return contactsManager?.tokenContact(forAddress: thread.contactIdentifier())
    }

    lazy var contactAvatarUrl: AsyncImageURL? = {
        if let contact = self.contact, let url = URL(string: contact.avatarPath) {
            return AsyncImageURL(url: url)
        }

        return nil
    }()

    var currentButton: SofaMessage.Button?

    var messageModels: [MessageModel] {
        return visibleMessages.flatMap { message in
            MessageModel(message: message)
        }
    }

    private(set) var messages: [Message] = [] {
        didSet {
            self.output.didReload()
        }
    }

    var visibleMessages: [Message] {
        return messages.filter { message -> Bool in
            message.isDisplayable
        }
    }

    func visibleMessage(at index: Int) -> Message {
        return visibleMessages[index]
    }

    func message(at index: Int) -> Message {
        return messages[index]
    }

    fileprivate var storageManager: TSStorageManager?

    fileprivate lazy var uiDatabaseConnection: YapDatabaseConnection = {
        let database = TSStorageManager.shared().database()!
        let dbConnection = database.newConnection()
        dbConnection.beginLongLivedReadTransaction()

        return dbConnection
    }()

    fileprivate lazy var mappings: YapDatabaseViewMappings = {
        let mappings = YapDatabaseViewMappings(groups: [self.thread.uniqueId], view: TSMessageDatabaseViewExtensionName)
        mappings.setIsReversed(true, forGroup: TSInboxGroup)

        return mappings
    }()

    fileprivate lazy var editingDatabaseConnection: YapDatabaseConnection? = {
        self.storageManager?.newDatabaseConnection()
    }()

    fileprivate func registerNotifications() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(yapDatabaseDidChange(notification:)), name: .YapDatabaseModified, object: nil)
    }

    func saveDraftIfNeeded(inputViewText: String?) {
        let thread = self.thread
        guard let text = inputViewText else { return }

        editingDatabaseConnection?.asyncReadWrite { transaction in
            thread.setDraft(text, transaction: transaction)
        }
    }

    @objc
    fileprivate func yapDatabaseDidChange(notification _: NSNotification) {
        let notifications = uiDatabaseConnection.beginLongLivedReadTransaction()

        // If changes do not affect current view, update and return without updating collection view
        // TODO: Since this is used in more than one place, we should look into abstracting this away, into our own
        // table/collection view backing model.
        let viewConnection = uiDatabaseConnection.ext(TSMessageDatabaseViewExtensionName) as? YapDatabaseViewConnection
        if let hasChangesForCurrentView = viewConnection?.hasChanges(for: notifications) as Bool?, hasChangesForCurrentView == false {
            uiDatabaseConnection.read { transaction in
                self.mappings.update(with: transaction)
            }

            return
        }

        var messageRowChanges = NSArray()
        var sectionChanges = NSArray()

        viewConnection?.getSectionChanges(&sectionChanges, rowChanges: &messageRowChanges, for: notifications, with: mappings)

        guard messageRowChanges.count > 0 else { return }

        uiDatabaseConnection.asyncRead { transaction in
            for change in messageRowChanges as! [YapDatabaseViewRowChange] {
                guard let dbExtension = transaction.ext(TSMessageDatabaseViewExtensionName) as? YapDatabaseViewTransaction else { return }

                switch change.type {
                case .insert:
                    guard let interaction = dbExtension.object(at: change.newIndexPath, with: self.mappings) as? TSInteraction else { return }

                    DispatchQueue.main.async {
                        let result = self.interactor.handleInteraction(interaction, shouldProcessCommands: true)
                        self.messages.append(result)

                        self.interactor.playSound(for: result)

                        if let incoming = interaction as? TSIncomingMessage, !incoming.wasRead {
                            incoming.markAsReadLocally()
                        }
                    }

                case .update:
                    let indexPath = change.indexPath
                    guard let interaction = dbExtension.object(at: indexPath, with: self.mappings) as? TSMessage else { return }

                    DispatchQueue.main.async {
                        let message = self.message(at: indexPath.row)
                        if let signalMessage = message.signalMessage as? TSOutgoingMessage, let newSignalMessage = interaction as? TSOutgoingMessage {
                            signalMessage.setState(newSignalMessage.messageState)
                        }

                        let updatedMessage = self.interactor.handleInteraction(interaction, shouldProcessCommands: false)
                        self.messages[indexPath.row] = updatedMessage
                    }
                default:
                    break
                }
            }
        }
    }

    func reloadDraft(completion: @escaping ((String?) -> Void)) {
        let thread = self.thread
        var placeholder: String?

        editingDatabaseConnection?.asyncReadWrite({ transaction in
            placeholder = thread.currentDraft(with: transaction)
        }, completionBlock: {
            DispatchQueue.main.async {
                completion(placeholder)
            }
        })
    }

    func displayState(for button: SofaMessage.Button?) -> DisplayState {
        if let button = button, let currentButton = self.currentButton {
            if button == currentButton {
                return .hide
            } else {
                return .hideAndShow
            }
        }

        if button == nil && currentButton == nil {
            return .doNothing
        } else if button == nil && currentButton != nil {
            return .hide
        } else {
            return .show
        }
    }

    func fetchAndUpdateBalance(completion: @escaping ((NSDecimalNumber, Error?) -> Void)) {
        interactor.fetchAndUpdateBalance(completion: completion)
    }

    func loadMessages() {
        uiDatabaseConnection.asyncRead { transaction in
            self.mappings.update(with: transaction)

            var messages = [Message]()

            for i in 0 ..< self.mappings.numberOfItems(inSection: 0) {
                let indexPath = IndexPath(row: Int(i), section: 0)
                guard let dbExtension = transaction.ext(TSMessageDatabaseViewExtensionName) as? YapDatabaseViewTransaction else { return }
                guard let interaction = dbExtension.object(at: indexPath, with: self.mappings) as? TSInteraction else { return }

                var shouldProcess = false
                if let message = interaction as? TSMessage, SofaType(sofa: message.body ?? "") == .paymentRequest {
                    shouldProcess = true
                }

                messages.append(self.interactor.handleInteraction(interaction, shouldProcessCommands: shouldProcess))
            }

            let current = Set(messages)
            let previous = Set(self.messages)
            let new = current.subtracting(previous).sorted { (message1, message2) -> Bool in
                // Signal splits media message in two separate messages, one with the attachments and one with text.
                // In this case two messages have the same Timestamp, we want to have the one with an attachment on top.
                if message1.date.compare(message2.date) == .orderedSame {
                    return message1.signalMessage.hasAttachments()
                }

                return message1.date.compare(message2.date) == .orderedAscending
            }

            DispatchQueue.main.async {
                self.messages = new
            }
        }
    }
}
