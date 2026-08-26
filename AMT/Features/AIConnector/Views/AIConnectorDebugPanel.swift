import SwiftUI

struct AIConnectorDebugPanel: View {
    let documentText: String

    @Bindable var viewModel: AIConnectorViewModel

    var body: some View {
        GroupBox("Qwen MLX Debug") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Picker("Input", selection: $viewModel.inputSource) {
                        ForEach(AIConnectorInputSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .frame(width: 170)

                    if viewModel.inputSource == .dummy {
                        Picker("Sample", selection: $viewModel.selectedSampleID) {
                            ForEach(AIConnectorSample.samples) { sample in
                                Text(sample.title).tag(sample.id)
                            }
                        }
                        .frame(maxWidth: 280)
                    } else {
                        Text("\(documentText.count) characters in document")
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Thinking", isOn: $viewModel.thinkingEnabled)
                        .toggleStyle(.checkbox)
                        .help("Reasoning internal tetap disembunyikan dari output.")
                }
                .disabled(viewModel.isRunning)

                Text(viewModel.inputPreview(documentText: documentText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.isInputTruncated(documentText: documentText) {
                    Label(
                        "Hanya 4.000 karakter pertama yang dikirim ke model.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                HStack(spacing: 8) {
                    if viewModel.isRunning {
                        Button("Cancel", action: viewModel.cancel)
                            .keyboardShortcut(.cancelAction)
                    } else {
                        Button("Run") {
                            viewModel.run(documentText: documentText)
                        }
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(!viewModel.canRun(documentText: documentText))

                        if case .failed = viewModel.state {
                            Button("Retry") {
                                viewModel.run(documentText: documentText)
                            }
                        }
                    }

                    Text(viewModel.state.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if case .downloading = viewModel.state {
                    ProgressView(value: viewModel.downloadProgress)
                        .progressViewStyle(.linear)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "xmark.octagon")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                ScrollView {
                    Text(viewModel.output.isEmpty ? "Model output akan tampil di sini." : viewModel.output)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .foregroundStyle(viewModel.output.isEmpty ? .secondary : .primary)
                        .padding(8)
                }
                .frame(minHeight: 100, maxHeight: 180)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(4)
        }
        .padding(8)
        .onDisappear(perform: viewModel.cancel)
    }
}
