import Cocoa

final class BindingSummaryView: NSView {
    private let heading = NSTextField(labelWithString: "")
    private var actionLabels: [Int: NSTextField] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        let card = UIStyle.makeCard()
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false

        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        heading.textColor = UIStyle.razerGreen
        heading.lineBreakMode = .byTruncatingTail
        content.addArrangedSubview(heading)

        let rows = [[1, 2, 3], [4, 5, 6], [7, 8, 9], [10, 11, 12], [13, 14], [15, 16, 17]]
        for slots in rows {
            let row = NSStackView(views: slots.map(makeCell))
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 6
            row.distribution = .fillEqually
            content.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }

        addSubview(card)
        card.addSubview(content)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 272),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            heading.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeCell(for slot: Int) -> NSStackView {
        let name = NSTextField(labelWithString: MappingLabels.button(slot))
        name.font = .systemFont(ofSize: 10, weight: .medium)
        name.textColor = .secondaryLabelColor
        name.lineBreakMode = .byTruncatingTail
        name.toolTip = name.stringValue

        let action = NSTextField(labelWithString: "")
        action.font = .systemFont(ofSize: 11, weight: .semibold)
        action.lineBreakMode = .byTruncatingTail
        actionLabels[slot] = action

        let cell = NSStackView(views: [name, action])
        cell.orientation = .vertical
        cell.alignment = .leading
        cell.spacing = 1
        name.widthAnchor.constraint(lessThanOrEqualTo: cell.widthAnchor).isActive = true
        action.widthAnchor.constraint(lessThanOrEqualTo: cell.widthAnchor).isActive = true
        return cell
    }

    func reload() {
        let config = ConfigManager.shared
        heading.stringValue = L10n.text("Button quick reference · %@", config.currentProfileName)
        heading.toolTip = heading.stringValue

        let mappings = config.mappingForCurrentProfile()
        for (slot, label) in actionLabels {
            let action = mappings[slot]
            let title = MappingLabels.action(action)
            label.stringValue = title
            if case .keySequence(let keys, _)? = action {
                let shortcut = keys.map { $0.formattedShortcut() }.joined(separator: ", ")
                label.toolTip = shortcut.isEmpty || shortcut == title ? title : "\(title) · \(shortcut)"
            } else {
                label.toolTip = title
            }
        }
    }
}
