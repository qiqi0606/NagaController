import Foundation

enum MappingLabels {
    static func button(_ index: Int) -> String {
        switch index {
        case 13: return L10n.text("DPI Up")
        case 14: return L10n.text("DPI Down")
        case 15: return L10n.text("Wheel Tilt Left")
        case 16: return L10n.text("Wheel Tilt Right")
        case 17: return L10n.text("Wheel Click")
        default: return L10n.text("Button %ld", index)
        }
    }

    static func action(_ action: ActionType?) -> String {
        guard let action else { return L10n.text("(Unassigned)") }
        switch action {
        case .keySequence(let keys, let description):
            return description ?? keys.map { $0.formattedShortcut() }.joined(separator: ", ")
        case .application(let path, let description):
            return description ?? L10n.text("App: %@", URL(fileURLWithPath: path).lastPathComponent)
        case .systemCommand(let command, let description):
            return description ?? L10n.text("Script: %@", command)
        case .textSnippet(let text, let description):
            let preview = text.replacingOccurrences(of: "\n", with: " ⏎ ")
            let truncated = preview.count > 40 ? String(preview.prefix(37)) + "…" : preview
            return description ?? L10n.text("Text: %@", truncated)
        case .macro(_, let description):
            return description ?? L10n.text("Macro")
        case .profileSwitch(let profile, let description):
            return description ?? L10n.text("Profile: %@", profile)
        case .hypershift:
            return L10n.text("Hypershift Modifier")
        case .mediaKey(let key, let description):
            return description ?? key.label
        }
    }
}
