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

protocol ChatInteractorOutput: class {
    func didCatchError(_ error: Error)

    func didFinishRequest()
    func didHandleSofaMessage(with buttons: [SofaMessage.Button], showKeyboard: Bool?)
}

final class ChatsInteractor {

    fileprivate var output: ChatInteractorOutput?
    private(set) var thread: TSThread

    init(output: ChatInteractorOutput, thread: TSThread) {
        self.output = output
        self.thread = thread

        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return
        }

        messageSender = appDelegate.messageSender
    }

    fileprivate var etherAPIClient: EthereumAPIClient {
        return EthereumAPIClient.shared
    }

    fileprivate var idAPIClient: IDAPIClient {
        return IDAPIClient.shared
    }

    lazy var processMediaDisposable: SMetaDisposable = {
        let disposable = SMetaDisposable()
        return disposable
    }()

    fileprivate var messageSender: MessageSender?

    func sendMessage(sofaWrapper: SofaWrapper, date: Date = Date(), completion: ((Bool) -> Void)? = nil) {
        let timestamp = NSDate.ows_millisecondsSince1970(for: date)
        let outgoingMessage = TSOutgoingMessage(timestamp: timestamp, in: thread, messageBody: sofaWrapper.content)

        messageSender?.send(outgoingMessage, success: {
            completion?(true)
            print("message sent")
        }, failure: { error in
            completion?(false)
            print(error)
        })
    }

    func send(image: UIImage) {
        guard let imageData = UIImagePNGRepresentation(image) else { return }

        let wrapper = SofaMessage(body: "")
        let timestamp = NSDate.ows_millisecondsSince1970(for: Date())
        let outgoingMessage = TSOutgoingMessage(timestamp: timestamp, in: thread, messageBody: wrapper.content)
        messageSender?.sendAttachmentData(imageData, contentType: "image/jpeg", sourceFilename: "image.jpeg", in: outgoingMessage, success: {
            print("Success")
        }, failure: { error in
            print("Failure: \(error)")
        })
    }

    func sendVideo(with url: URL) {
        guard let videoData = try? Data(contentsOf: url) else { return }

        let wrapper = SofaMessage(body: "")
        let timestamp = NSDate.ows_millisecondsSince1970(for: Date())
        let outgoingMessage = TSOutgoingMessage(timestamp: timestamp, in: thread, messageBody: wrapper.content)

        messageSender?.sendAttachmentData(videoData, contentType: "video/mp4", sourceFilename: "video.mp4", in: outgoingMessage, success: {
            self.output?.didFinishRequest()
            print("Success")
        }, failure: { error in
            self.output?.didFinishRequest()
            print("Failure: \(error)")
        })
    }

    func sendPayment(in value: NSDecimalNumber?, completion: ((Bool) -> Void)? = nil) {
        guard let value = value else {
            return
        }

        guard let tokenId = self.thread.contactIdentifier() else {
            return
        }

        idAPIClient.retrieveContact(username: tokenId) { user in
            guard let user = user else { return }

            let parameters: [String: Any] = [
                "from": Cereal.shared.paymentAddress,
                "to": user.paymentAddress,
                "value": value.toHexString
            ]

            self.sendPayment(with: parameters, completion: completion)
        }
    }

    func fetchAndUpdateBalance(completion: @escaping ((NSDecimalNumber, Error?) -> Void)) {
        etherAPIClient.getBalance(address: Cereal.shared.paymentAddress) { balance, error in
            completion(balance, error)
        }
    }

    func sendPayment(with parameters: [String: Any], completion: ((Bool) -> Void)? = nil) {
        etherAPIClient.createUnsignedTransaction(parameters: parameters) { transaction, error in

            guard let transaction = transaction as String? else {
                if let error = error as Error? {
                    self.output?.didFinishRequest()
                    self.output?.didCatchError(error)
                    completion?(false)
                }

                return
            }

            let signedTransaction = "0x\(Cereal.shared.signWithWallet(hex: transaction))"

            self.etherAPIClient.sendSignedTransaction(originalTransaction: transaction, transactionSignature: signedTransaction) { json, error in

                self.output?.didFinishRequest()

                if let error = error as Error? {
                    var message = "Something went wrong"
                    if let json = json?.dictionary as [String: Any]?, let jsonMessage = json["message"] as? String {
                        message = jsonMessage
                    }

                    self.output?.didCatchError(error)
                    completion?(false)

                } else if let json = json?.dictionary {
                    guard let txHash = json["tx_hash"] as? String else { fatalError("Error recovering transaction hash.") }
                    guard let value = parameters["value"] as? String else { return }

                    let payment = SofaPayment(txHash: txHash, valueHex: value)
                    self.sendMessage(sofaWrapper: payment)

                    completion?(true)
                }
            }
        }
    }

    func handleInvalidKeyError(_: TSInvalidIdentityKeyErrorMessage) {
    }

    /// Handle incoming interactions or previous messages when restoring a conversation.
    ///
    /// - Parameters:
    ///   - interaction: the interaction to handle. Incoming/outgoing messages, wrapping SOFA structures.
    ///   - shouldProcessCommands: If true, will process a sofa wrapper. This means replying to requests, displaying payment UI etc.
    ///

    func handleInteraction(_ interaction: TSInteraction, shouldProcessCommands: Bool = false) -> Message {
        if let interaction = interaction as? TSInvalidIdentityKeySendingErrorMessage {
            DispatchQueue.main.async {
                self.handleInvalidKeyError(interaction)
            }

            return Message(sofaWrapper: nil, signalMessage: interaction, date: interaction.dateForSorting(), isOutgoing: false)
        }

        if let message = interaction as? TSMessage, shouldProcessCommands {
            let type = SofaType(sofa: message.body)
            switch type {
            case .metadataRequest:
                let metadataResponse = SofaMetadataResponse(metadataRequest: SofaMetadataRequest(content: message.body ?? ""))
                sendMessage(sofaWrapper: metadataResponse)
            default:
                break
            }
        }

        /// TODO: Simplify how we deal with interactions vs text messages.
        /// Since now we know we can expande the TSInteraction stored properties, maybe we can merge some of this together.
        if let interaction = interaction as? TSOutgoingMessage {
            let sofaWrapper = SofaWrapper.wrapper(content: interaction.body ?? "")
            let message = Message(sofaWrapper: sofaWrapper, signalMessage: interaction, date: interaction.dateForSorting(), isOutgoing: true)

            if interaction.hasAttachments() {
                message.messageType = "Image"
            } else if let payment = SofaWrapper.wrapper(content: interaction.body ?? "") as? SofaPayment {
                message.messageType = "Actionable"
                message.attributedTitle = NSAttributedString(string: "Payment sent", attributes: [NSForegroundColorAttributeName: Theme.outgoingMessageTextColor, NSFontAttributeName: Theme.medium(size: 17)])
                message.attributedSubtitle = NSAttributedString(string: EthereumConverter.balanceAttributedString(forWei: payment.value, exchangeRate: EthereumAPIClient.shared.exchangeRate).string, attributes: [NSForegroundColorAttributeName: Theme.outgoingMessageTextColor, NSFontAttributeName: Theme.regular(size: 15)])
            }

            return message
        } else if let interaction = interaction as? TSIncomingMessage {
            let sofaWrapper = SofaWrapper.wrapper(content: interaction.body ?? "")
            let message = Message(sofaWrapper: sofaWrapper, signalMessage: interaction, date: interaction.dateForSorting(), isOutgoing: false, shouldProcess: shouldProcessCommands && interaction.paymentState == .none)

            if interaction.hasAttachments() {
                message.messageType = "Image"
            } else if let sofaMessage = sofaWrapper as? SofaMessage {
                output?.didHandleSofaMessage(with: sofaMessage.buttons, showKeyboard: sofaMessage.showKeyboard)
            } else if let paymentRequest = sofaWrapper as? SofaPaymentRequest {
                message.messageType = "Actionable"
                message.title = "Payment request"
                message.attributedSubtitle = EthereumConverter.balanceAttributedString(forWei: paymentRequest.value, exchangeRate: EthereumAPIClient.shared.exchangeRate)
            } else if let payment = sofaWrapper as? SofaPayment {
                output?.didFinishRequest()
                message.messageType = "Actionable"
                message.attributedTitle = NSAttributedString(string: "Payment received", attributes: [NSForegroundColorAttributeName: Theme.incomingMessageTextColor, NSFontAttributeName: Theme.medium(size: 17)])
                message.attributedSubtitle = NSAttributedString(string: EthereumConverter.balanceAttributedString(forWei: payment.value, exchangeRate: EthereumAPIClient.shared.exchangeRate).string, attributes: [NSForegroundColorAttributeName: Theme.incomingMessageTextColor, NSFontAttributeName: Theme.regular(size: 15)])
            }

            return message
        } else {
            return Message(sofaWrapper: nil, signalMessage: interaction as! TSMessage, date: interaction.dateForSorting(), isOutgoing: false)
        }
    }

    func playSound(for message: Message) {
        if message.isOutgoing {
            if message.sofaWrapper?.type == .paymentRequest {
                SoundPlayer.playSound(type: .requestPayment)
            } else if message.sofaWrapper?.type == .payment {
                SoundPlayer.playSound(type: .paymentSend)
            } else {
                SoundPlayer.playSound(type: .messageSent)
            }
        } else {
            SoundPlayer.playSound(type: .messageReceived)
        }
    }

    @discardableResult static func getOrCreateThread(for address: String) -> TSThread {
        var thread: TSThread?

        TSStorageManager.shared().dbConnection?.readWrite { transaction in
            var recipient = SignalRecipient(textSecureIdentifier: address, with: transaction)

            var shouldRequestContactsRefresh = false

            if recipient == nil {
                recipient = SignalRecipient(textSecureIdentifier: address, relay: nil)
                shouldRequestContactsRefresh = true
            }

            recipient?.save(with: transaction)
            thread = TSContactThread.getOrCreateThread(withContactId: address, transaction: transaction)

            if shouldRequestContactsRefresh == true {
                self.requestContactsRefresh()
            }

            if thread?.archivalDate() != nil {
                thread?.unarchiveThread(with: transaction)
            }
        }

        return thread!
    }

    fileprivate static func requestContactsRefresh() {
        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        appDelegate?.contactsManager.refreshContacts()
    }

    func asyncProcess(signals: [SSignal]) {
        let queue = SQueue()
        var combinedSignal: SSignal?

        for signal in signals {
            if combinedSignal == nil {
                combinedSignal = signal.start(on: queue)
            } else {
                combinedSignal = combinedSignal?.then(signal).start(on: queue)
            }
        }

        let array = [Any]()
        let signal = combinedSignal?.reduceLeft(array, with: { itemDescriptions, item in
            if var descriptions = itemDescriptions as? [[String: Any]] {
                if let description = item as? [String: Any] {
                    descriptions.append(description)
                }

                return descriptions
            }

            return nil

        }).deliver(on: SQueue.main()).start { itemDescriptions in

            var mediaDescriptions = [[String: Any]]()

            if let itemDescriptions = itemDescriptions as? [[String: Any]] {

                for description in itemDescriptions {
                    if description["localImage"] != nil ||
                        description["remoteImage"] != nil ||
                        description["downloadImage"] != nil ||
                        description["downloadDocument"] != nil ||
                        description["downloadExternalGif"] != nil ||
                        description["downloadExternalImage"] != nil ||
                        description["remoteDocument"] != nil ||
                        description["remoteCachedDocument"] != nil ||
                        description["assetImage"] != nil ||
                        description["assetVideo"] != nil {

                        mediaDescriptions.append(description)
                    }
                }
            }

            if !mediaDescriptions.isEmpty {
                for description in mediaDescriptions {

                    var mediaData: [String: Any]?
                    var contentType = ""

                    if let assetImage = description["assetImage"] as? [String: Any] {
                        mediaData = assetImage
                        contentType = "image/jpeg"
                    } else if let localImage = description["localImage"] as? [String: Any] {
                        mediaData = localImage
                        contentType = "image/jpeg"
                    } else if let assetVideo = description["assetVideo"] as? [String: Any] {
                        mediaData = assetVideo
                        contentType = "video/mov"
                    } else if let libraryVideo = description["libraryVideo"] as? [String: Any] {
                        mediaData = libraryVideo
                        contentType = "video/mov"
                    }

                    let wrapper = SofaMessage(body: "")
                    let timestamp = NSDate.ows_millisecondsSince1970(for: Date())

                    if let thumbnailData = mediaData?["thumbnailData"] as? Data {
                        let outgoingMessage = TSOutgoingMessage(timestamp: timestamp, in: self.thread, messageBody: wrapper.content)
                        self.messageSender?.sendAttachmentData(thumbnailData, contentType: contentType, sourceFilename: "File.jpeg", in: outgoingMessage, success: {
                            print("Success")
                        }, failure: { error in
                            print("Failure: \(error)")
                        })
                    }
                }
            }
        }

        if let signal = signal as SDisposable? {
            processMediaDisposable.setDisposable(signal)
        }
    }
}
