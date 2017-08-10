import Foundation
import UIKit
import TinyConstraints

enum MessagePositionType {
    case single
    case top
    case middle
    case bottom
}

/* Messages Basic Cell:
 This UITableViewCell is the base cell for the different
 advanced cells used in messages. It provides the ground layout. */

class MessagesBasicCell: UITableViewCell {

    private let contentLayoutGuide = UILayoutGuide()
    private let leftLayoutGuide = UILayoutGuide()
    private let centerLayoutGuide = UILayoutGuide()
    private let rightLayoutGuide = UILayoutGuide()

    private(set) var leftWidthConstraint: NSLayoutConstraint?
    private(set) var rightWidthConstraint: NSLayoutConstraint?

    private(set) lazy var bubbleView: UIView = {
        let view = UIView()
        view.clipsToBounds = true

        return view
    }()

    private(set) lazy var messagesCornerView: MessagesCornerView = MessagesCornerView()

    private(set) lazy var avatarImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.layer.cornerRadius = 18

        return view
    }()

    private let margin: CGFloat = 10
    private let avatarRadius: CGFloat = 44

    private var bubbleLeftConstraint: NSLayoutConstraint?
    private var bubbleRightConstraint: NSLayoutConstraint?
    private var bubbleLeftConstantConstraint: NSLayoutConstraint?
    private var bubbleRightConstantConstraint: NSLayoutConstraint?

    private var contentLayoutGuideTopConstraint: NSLayoutConstraint?

    var isOutGoing: Bool = false {
        didSet {
            if isOutGoing {
                bubbleRightConstraint?.isActive = false
                bubbleLeftConstantConstraint?.isActive = false
                bubbleLeftConstraint?.isActive = true
                bubbleRightConstantConstraint?.isActive = true
            } else {
                bubbleLeftConstraint?.isActive = false
                bubbleRightConstantConstraint?.isActive = false
                bubbleRightConstraint?.isActive = true
                bubbleLeftConstantConstraint?.isActive = true
            }
        }
    }

    var positionType: MessagePositionType = .single {
        didSet {
            let isFirstMessage = positionType == .single || positionType == .top
            contentLayoutGuideTopConstraint?.constant = isFirstMessage ? 8 : 4

            let isAvatarHidden = positionType == .top || positionType == .middle || isOutGoing
            avatarImageView.isHidden = isAvatarHidden

            messagesCornerView.setImage(for: positionType, isOutGoing: isOutGoing, isPayment: self is MessagesPaymentCell)
        }
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = nil
        selectionStyle = .none
        contentView.autoresizingMask = [.flexibleHeight]

        /* Layout Guides:
         The leftLayoutGuide reserves space for an optional avatar.
         The centerLayoutGuide defines the space for the message content.
         The rightLayoutGuide reserves space for an optional error indicator. */

        contentView.addLayoutGuide(contentLayoutGuide)
        contentView.addLayoutGuide(leftLayoutGuide)
        contentView.addLayoutGuide(centerLayoutGuide)
        contentView.addLayoutGuide(rightLayoutGuide)

        contentLayoutGuideTopConstraint = contentLayoutGuide.top(to: contentView, offset: 2)
        contentLayoutGuide.left(to: contentView)
        contentLayoutGuide.bottom(to: contentView)
        contentLayoutGuide.right(to: contentView)
        contentLayoutGuide.width(UIScreen.main.bounds.width)

        leftLayoutGuide.top(to: contentLayoutGuide)
        leftLayoutGuide.left(to: contentLayoutGuide, offset: margin)
        leftLayoutGuide.bottom(to: contentLayoutGuide)

        centerLayoutGuide.top(to: contentLayoutGuide)
        centerLayoutGuide.leftToRight(of: leftLayoutGuide)
        centerLayoutGuide.bottom(to: contentLayoutGuide)

        rightLayoutGuide.top(to: contentLayoutGuide)
        rightLayoutGuide.leftToRight(of: centerLayoutGuide)
        rightLayoutGuide.bottom(to: contentLayoutGuide)
        rightLayoutGuide.right(to: contentLayoutGuide, offset: -margin)

        leftWidthConstraint = leftLayoutGuide.width(avatarRadius)
        rightWidthConstraint = rightLayoutGuide.width(0)

        /* Avatar Image View:
         A UIImageView for showing an optional avatar of the user. */

        contentView.addSubview(avatarImageView)
        avatarImageView.left(to: leftLayoutGuide)
        avatarImageView.bottom(to: leftLayoutGuide)
        avatarImageView.right(to: leftLayoutGuide, offset: -8)
        avatarImageView.height(to: avatarImageView, avatarImageView.widthAnchor)

        /* Bubble View:
         The container that can be filled with a message, image or
         even a payment request. */

        contentView.addSubview(bubbleView)
        bubbleView.top(to: centerLayoutGuide)
        bubbleView.bottom(to: centerLayoutGuide)

        bubbleLeftConstraint = bubbleView.left(to: centerLayoutGuide, offset: 50, relation: .equalOrGreater)
        bubbleRightConstraint = bubbleView.right(to: centerLayoutGuide, offset: -50, relation: .equalOrLess)
        bubbleLeftConstantConstraint = bubbleView.left(to: centerLayoutGuide, isActive: false)
        bubbleRightConstantConstraint = bubbleView.right(to: centerLayoutGuide, isActive: false)

        bubbleView.addSubview(messagesCornerView)
        messagesCornerView.edges(to: bubbleView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        avatarImageView.image = nil
        messagesCornerView.image = nil
    }
}
