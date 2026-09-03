import SwiftUI

private struct AIConnectorDebugPanelActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct AIConnectorDefinitionDiagnosticsVisibilityKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var showAIConnectorDebugPanel: (() -> Void)? {
        get { self[AIConnectorDebugPanelActionKey.self] }
        set { self[AIConnectorDebugPanelActionKey.self] = newValue }
    }

    var showAIConnectorDefinitionDiagnostics: Binding<Bool>? {
        get { self[AIConnectorDefinitionDiagnosticsVisibilityKey.self] }
        set { self[AIConnectorDefinitionDiagnosticsVisibilityKey.self] = newValue }
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

            Toggle(
                "Tampilkan definisi selaras (Debug)",
                isOn: showDefinitionDiagnostics ?? .constant(false)
            )
            .disabled(showDefinitionDiagnostics == nil)
        }
    }

    @FocusedValue(\.showAIConnectorDefinitionDiagnostics)
    private var showDefinitionDiagnostics
}
