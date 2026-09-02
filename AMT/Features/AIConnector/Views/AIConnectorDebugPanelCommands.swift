import SwiftUI

private struct AIConnectorDebugPanelActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var showAIConnectorDebugPanel: (() -> Void)? {
        get { self[AIConnectorDebugPanelActionKey.self] }
        set { self[AIConnectorDebugPanelActionKey.self] = newValue }
    }
}

/// Adds the AI Connector diagnostics entry point to the macOS View menu.
struct AIConnectorDebugPanelCommands: Commands {
    @FocusedValue(\.showAIConnectorDebugPanel)
    private var showDebugPanel

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Tampilkan Debug Panel AI Connector") {
                showDebugPanel?()
            }
            .disabled(showDebugPanel == nil)
            .keyboardShortcut("d", modifiers: [.command, .option])
        }
    }
}
