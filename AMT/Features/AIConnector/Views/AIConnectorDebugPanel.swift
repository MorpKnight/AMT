import Foundation
import SwiftUI

struct AIConnectorDebugPanel: View {
    let documentText: String

    @Bindable var viewModel: AIConnectorViewModel

    var body: some View {
        GroupBox("Suggestion — Eksperimental") {
            VStack(alignment: .leading, spacing: 10) {
                AIConnectorPanelHeader()
                AIConnectorSafetyNotice()

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Strategi review", selection: $viewModel.reviewMode) {
                            ForEach(AIConnectorReviewMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        Text(viewModel.reviewMode.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(width: 220, alignment: .leading)

                    if viewModel.reviewMode.usesModel {
                        VStack(alignment: .leading, spacing: 4) {
                            Picker("Model", selection: $viewModel.modelVariant) {
                                ForEach(AIConnectorModelVariant.allCases) { model in
                                    Text(model.title).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            Text("\(viewModel.modelVariant.downloadEstimate) • rev \(viewModel.modelVariant.shortRevision)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 220, alignment: .leading)
                    }

                    Picker("Sumber input", selection: $viewModel.inputSource) {
                        ForEach(AIConnectorInputSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180, alignment: .leading)

                    if viewModel.inputSource == .dummy {
                        Picker("Fixture", selection: $viewModel.selectedSampleID) {
                            ForEach(AIConnectorSample.samples) { sample in
                                Text(sample.title).tag(sample.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 280)
                    } else {
                        Label("\(documentText.count) karakter", systemImage: "character.textbox")
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Toggle("Thinking eksperimental", isOn: $viewModel.thinkingEnabled)
                        .toggleStyle(.checkbox)
                        .help("Mode eksperimental; reasoning internal tetap disembunyikan.")
                }
                .disabled(viewModel.isRunning)
                .padding(10)
                .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))

                Text(viewModel.inputPreview(documentText: documentText))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(.quaternary.opacity(0.65), lineWidth: 1)
                    )

                if viewModel.inputWasTruncated(documentText: documentText) {
                    Label(
                        "Preview dibatasi ke 4.000 karakter pertama; analisis tetap memakai seluruh dokumen.",
                        systemImage: "scissors"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 2)
                }

                if viewModel.inputSource == .dummy {
                    DisclosureGroup("Sinyal yang diharapkan (Debug)") {
                        Text(viewModel.selectedSample.expectedSignal)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }

                if let segmentation = viewModel.segmentationResult {
                    AIConnectorSegmentationSummary(
                        segmentation: segmentation,
                        skippedSegmentCount: viewModel.skippedSegmentCount,
                        batchSizes: viewModel.queueBatchSizes
                    )
                } else {
                    Text("Dokumen diproses seluruhnya per kalimat; queue berjalan serial dalam batch 12.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                }

                if !viewModel.currentSegmentPreview.isEmpty, viewModel.isRunning {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target saat ini")
                            .font(.caption.weight(.semibold))
                        Text(viewModel.currentSegmentPreview)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(.blue.opacity(0.22), lineWidth: 1)
                    )
                }

                if viewModel.isRunning, !viewModel.currentGlossaryMatches.isEmpty {
                    DisclosureGroup {
                        ScrollView(.vertical) {
                            GlossaryMatchesList(matches: viewModel.currentGlossaryMatches)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, maxHeight: 180, alignment: .topLeading)
                    } label: {
                        AIConnectorDisclosureHeader(
                            title: "Kandidat glossary segmen saat ini",
                            count: viewModel.currentGlossaryMatches.count,
                            systemImage: "books.vertical",
                            tint: .purple
                        )
                    }
                }

                if !viewModel.isRunning, !viewModel.glossarySnapshots.isEmpty {
                    DisclosureGroup {
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(viewModel.glossarySnapshots) { snapshot in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Segmen \(snapshot.segment.id)")
                                            .font(.caption.weight(.semibold))
                                        Text(snapshot.segment.targetText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                        GlossaryMatchesList(matches: snapshot.matches)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, maxHeight: 240, alignment: .topLeading)
                    } label: {
                        AIConnectorDisclosureHeader(
                            title: "Kandidat glossary hasil run",
                            count: viewModel.glossaryCandidateCount,
                            systemImage: "books.vertical",
                            tint: .purple
                        )
                    }
                }

                HStack(spacing: 8) {
                    if viewModel.isRunning {
                        Button {
                            viewModel.cancel()
                        } label: {
                            Label("Batalkan", systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .keyboardShortcut(.cancelAction)
                    } else {
                        Button {
                            viewModel.run(documentText: documentText)
                        } label: {
                            Label("Jalankan review", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(!viewModel.canRun(documentText: documentText))

                        Button {
                            viewModel.runBenchmark()
                        } label: {
                            Label(
                                viewModel.reviewMode == .deterministic
                                    ? "Uji baseline"
                                    : "Benchmark \(AIConnectorSample.samples.count) fixture",
                                systemImage: "checklist"
                            )
                        }
                        .buttonStyle(.bordered)
                        .help(viewModel.reviewMode == .deterministic
                            ? "Jalankan seluruh fixture dengan aturan deterministik tanpa mengunduh model."
                            : "Jalankan seluruh fixture dengan model dan safety boundary yang dipilih.")
                        .disabled(!viewModel.canRunBenchmark)

                        if case .failed = viewModel.state {
                            Button {
                                viewModel.run(documentText: documentText)
                            } label: {
                                Label("Coba lagi", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Spacer(minLength: 0)
                    AIConnectorStateBadge(state: viewModel.state)
                }

                if case let .downloading(progress) = viewModel.state {
                    AIConnectorProgressCard(
                        title: "Mengunduh model",
                        detail: "Model akan tersimpan di cache lokal setelah selesai.",
                        progress: progress
                    )
                }

                if case let .reviewing(current, total) = viewModel.state {
                    AIConnectorProgressCard(
                        title: "Meninjau kalimat \(current) dari \(total)",
                        detail: "\(viewModel.generationProgress) karakter output • hasil belum ditampilkan sebelum lolos pemeriksaan",
                        progress: Double(max(current - 1, 0)) / Double(max(total, 1))
                    )
                }

                if case .segmenting = viewModel.state {
                    AIConnectorProgressCard(
                        title: "Menyiapkan teks",
                        detail: "Membagi dokumen menjadi segmen kalimat.",
                        progress: nil
                    )
                }

                if case .loading = viewModel.state {
                    AIConnectorProgressCard(
                        title: "Memuat model",
                        detail: "Menyiapkan model lokal sebelum review dimulai.",
                        progress: nil
                    )
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "xmark.octagon")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                }

                if let summary = viewModel.runSummary {
                    AIConnectorRunSummaryView(summary: summary)
                }

                if viewModel.currentQueueState != nil || !viewModel.queueBatchSizes.isEmpty {
                    AIConnectorQueueDiagnosticsView(
                        state: viewModel.currentQueueState,
                        batchIndex: viewModel.currentBatchIndex,
                        batchSize: viewModel.currentBatchSize,
                        batchSizes: viewModel.queueBatchSizes
                    )
                }

                if let evaluation = viewModel.fixtureEvaluation {
                    AIConnectorFixtureEvaluationView(evaluation: evaluation)
                }

                if let benchmarkReport = viewModel.benchmarkReport {
                    AIConnectorBenchmarkReportView(report: benchmarkReport)
                } else if let benchmarkSummary = viewModel.benchmarkSummary {
                    AIConnectorBenchmarkSummaryView(summary: benchmarkSummary)
                }

                if let metrics = viewModel.latestGenerationMetrics {
                    AIConnectorGenerationMetricsView(metrics: metrics)
                }

                if !viewModel.validatedReviews.isEmpty {
                    DisclosureGroup {
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(viewModel.validatedReviews) { review in
                                    AIValidatedReviewRow(review: review)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, maxHeight: 240, alignment: .topLeading)
                    } label: {
                        AIConnectorDisclosureHeader(
                            title: "Hasil pipeline tervalidasi",
                            count: viewModel.validatedReviews.count,
                            systemImage: "checkmark.shield.fill",
                            tint: .green
                        )
                    }
                }

                #if DEBUG
                if !viewModel.rejectedReviews.isEmpty {
                    DisclosureGroup {
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(viewModel.rejectedReviews) { rejection in
                                    AIReviewRejectionRow(rejection: rejection)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: 240, alignment: .topLeading)
                        .padding(.top, 4)
                    } label: {
                        AIConnectorDisclosureHeader(
                            title: "Output model ditolak",
                            count: viewModel.rejectedReviews.count,
                            systemImage: "exclamationmark.triangle.fill",
                            tint: .orange
                        )
                    }
                }
                #endif

                VStack(alignment: .leading, spacing: 8) {
                    AIConnectorSectionHeader(
                        title: "Output ringkas",
                        subtitle: "Salinan hasil yang lolos pemeriksaan.",
                        systemImage: "doc.plaintext"
                    )
                    ScrollView {
                        Text(viewModel.output.isEmpty
                            ? "Belum ada hasil yang lolos pemeriksaan."
                            : viewModel.output)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .foregroundStyle(viewModel.output.isEmpty ? .secondary : .primary)
                            .padding(10)
                    }
                    .frame(minHeight: 90, maxHeight: 180)
                    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(.quaternary.opacity(0.65), lineWidth: 1)
                    )
                }
            }
            .padding(8)
        }
        .padding(8)
        .onDisappear(perform: viewModel.cancel)
        .onChange(of: viewModel.inputSource) { _, _ in
            viewModel.resetInputMetadata()
        }
        .onChange(of: viewModel.selectedSampleID) { _, _ in
            viewModel.resetInputMetadata()
        }
        .onChange(of: viewModel.reviewMode) { _, _ in
            viewModel.resetInputMetadata()
        }
        .onChange(of: viewModel.modelVariant) { _, _ in
            viewModel.resetInputMetadata()
        }
        .onChange(of: documentText) { _, _ in
            viewModel.resetInputMetadata()
        }
    }
}

private struct GlossaryMatchesList: View {
    let matches: [LegalDictionaryMatch]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(matches) { match in
                GlossaryMatchRow(match: match)
            }
        }
    }
}

private struct AIConnectorPanelHeader: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text("Review bahasa hukum")
                    .font(.headline)
                Text("Eksperimen lokal untuk menguji segmentasi, glossary, dan safety gate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text("DEBUG")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.orange.opacity(0.12), in: Capsule())
        }
    }
}

private struct AIConnectorSafetyNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Eksperimen, bukan nasihat hukum")
                    .font(.subheadline.weight(.semibold))
                Text("Output hanya saran awal. Jangan masukkan dokumen rahasia; dokumen tidak diubah otomatis.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(.orange.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct AIConnectorSegmentationSummary: View {
    let segmentation: AITextSegmentationResult
    let skippedSegmentCount: Int
    let batchSizes: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AIConnectorSectionHeader(
                title: "Analisis dokumen",
                subtitle: "Segmentasi yang dipakai pada Run terakhir.",
                systemImage: "text.magnifyingglass"
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                spacing: 8
            ) {
                AIConnectorMetricTile(
                    value: "\(segmentation.segments.count)",
                    label: "Segmen",
                    tint: .blue
                )
                AIConnectorMetricTile(
                    value: "\(segmentation.headingCount)",
                    label: "Heading",
                    tint: .purple
                )
                AIConnectorMetricTile(
                    value: "\(segmentation.tooLongSegmentCount)",
                    label: "Terlalu panjang",
                    tint: .orange
                )
                AIConnectorMetricTile(
                    value: "\(skippedSegmentCount)",
                    label: "Dilewati",
                    tint: .secondary
                )
            }

            Text(batchDescription)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
    }

    private var batchDescription: String {
        guard !batchSizes.isEmpty else { return "Batch queue: belum dimulai" }
        return "Batch queue: " + batchSizes.map(String.init).joined(separator: " / ")
            + " • serial"
    }
}

private struct AIConnectorQueueDiagnosticsView: View {
    let state: AIConnectorQueueState?
    let batchIndex: Int?
    let batchSize: Int?
    let batchSizes: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AIConnectorSectionHeader(
                title: "Queue diagnostics",
                subtitle: "Pemrosesan serial; batch hanya mengatur back-pressure.",
                systemImage: "arrow.trianglehead.2.clockwise"
            )

            HStack(spacing: 8) {
                if let state {
                    AIConnectorDiagnosticPill(
                        value: state.rawValue,
                        label: "state",
                        tint: state == .rejected || state == .failed ? .orange : .blue
                    )
                }
                if let batchIndex, let batchSize {
                    AIConnectorDiagnosticPill(
                        value: "\(batchIndex)/\(batchSizes.count)",
                        label: "batch (\(batchSize))",
                        tint: .purple
                    )
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct AIConnectorDiagnosticPill: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.caption2.monospacedDigit().weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.11), in: Capsule())
    }
}

private struct AIConnectorSectionHeader: View {
    let title: String
    let subtitle: String?
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AIConnectorMetricTile: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AIConnectorStateBadge: View {
    let state: AIConnectorRunState

    var body: some View {
        Label(state.title, systemImage: state.iconName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(state.tint.opacity(0.11), in: Capsule())
    }
}

private struct AIConnectorProgressCard: View {
    let title: String
    let detail: String
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if let progress {
                    Text("\(Int(max(0, min(1, progress)) * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let progress {
                ProgressView(value: max(0, min(1, progress)))
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct AIConnectorFixtureEvaluationView: View {
    let evaluation: AIConnectorFixtureEvaluation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AIConnectorSectionHeader(
                title: evaluation.passed ? "Fixture lulus" : "Fixture belum lulus",
                subtitle: evaluation.sample.title,
                systemImage: evaluation.passed
                    ? "checkmark.seal.fill"
                    : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(evaluation.passed ? .green : .orange)

            Text("Expected: \(evaluation.sample.expectedSignal)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(actualSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(evaluation.detail)
                .font(.caption)
                .foregroundStyle(evaluation.passed ? .green : .orange)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((evaluation.passed ? Color.green : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private var actualSummary: String {
        guard let actualStatus = evaluation.actualStatus else {
            return "Actual: tidak ada hasil valid."
        }

        let replacement = evaluation.actualReplacement.map { " → \($0)" } ?? ""
        return "Actual: \(actualStatus.displayTitle)\(replacement)"
    }
}

private struct AIConnectorBenchmarkSummaryView: View {
    let summary: AIConnectorBenchmarkSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            AIConnectorSectionHeader(
                title: "Benchmark fixture",
                subtitle: "\(summary.reviewMode.title) • \(summary.modelVariant.title)",
                systemImage: "checklist"
            )

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(summary.passedCount)/\(summary.totalCount)")
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(summary.passedCount == summary.totalCount ? .green : .orange)
                Text("fixture memenuhi expected signal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(String(format: "%.2f dtk", summary.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(summary.evaluations) { evaluation in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: evaluation.passed
                            ? "checkmark.circle.fill"
                            : "xmark.circle.fill")
                            .foregroundStyle(evaluation.passed ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(evaluation.sample.title)
                                .font(.caption.weight(.semibold))
                            Text(actualSummary(for: evaluation))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(evaluation.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
    }

    private func actualSummary(for evaluation: AIConnectorFixtureEvaluation) -> String {
        guard let status = evaluation.actualStatus else {
            return "Actual: tidak ada hasil tervalidasi."
        }

        let replacement = evaluation.actualReplacement.map { " → \($0)" } ?? ""
        return "Actual: \(status.displayTitle)\(replacement)"
    }
}

private struct AIConnectorBenchmarkReportView: View {
    let report: AIConnectorBenchmarkReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AIConnectorSectionHeader(
                    title: "Quality gate P0.9",
                    subtitle: "\(report.reviewMode.title) • \(report.modelVariant.title)",
                    systemImage: "checkmark.shield"
                )
                Spacer(minLength: 0)
                Text(report.qualityGate.decision.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(report.qualityGate.passed ? .green : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (report.qualityGate.passed ? Color.green : Color.orange).opacity(0.12),
                        in: Capsule()
                    )
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(report.passedCount)/\(report.totalCount)")
                    .font(.title3.monospacedDigit().weight(.bold))
                Text("fixture sesuai expected signal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(String(format: "%.2f dtk", report.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 112), spacing: 8)],
                spacing: 8
            ) {
                AIConnectorMetricTile(
                    value: "\(report.qualityGate.languagePassCount)/\(report.qualityGate.languageTotal)",
                    label: "Bahasa",
                    tint: .blue
                )
                AIConnectorMetricTile(
                    value: "\(report.qualityGate.neutralSafetyPassCount)/\(report.qualityGate.neutralSafetyTotal)",
                    label: "Neutral/safety",
                    tint: .green
                )
                AIConnectorMetricTile(
                    value: "\(report.qualityGate.schemaCompliantCount)/\(report.qualityGate.schemaTotal)",
                    label: "Schema valid",
                    tint: .blue
                )
                AIConnectorMetricTile(
                    value: "\(report.qualityGate.safetyContainedCount)/\(report.qualityGate.safetyTotal)",
                    label: "Safety contained",
                    tint: .green
                )
                AIConnectorMetricTile(
                    value: "\(report.qualityGate.usableValidatedOutputCount)",
                    label: "Output tervalidasi",
                    tint: .mint
                )
                AIConnectorMetricTile(
                    value: "\(report.qualityGate.exactExpectationPassCount)",
                    label: "Expected signal",
                    tint: .purple
                )
                AIConnectorMetricTile(
                    value: report.circuitBreakerActivated ? "Aktif" : "Tidak",
                    label: "Circuit breaker",
                    tint: report.circuitBreakerActivated ? .orange : .green
                )
                AIConnectorMetricTile(
                    value: "\(report.qualityGate.truncatedCount)",
                    label: "Token limit",
                    tint: .orange
                )
                AIConnectorMetricTile(
                    value: "\(report.qualityGate.repetitionCount)",
                    label: "Repetition ≥ 0,2",
                    tint: .orange
                )
                AIConnectorMetricTile(
                    value: "\(report.qualityGate.reasoningLeakCount)",
                    label: "Reasoning leak",
                    tint: .red
                )
                AIConnectorMetricTile(
                    value: "\(report.records.filter(\.cacheHit).count)",
                    label: "Cache hit",
                    tint: .blue
                )
                AIConnectorMetricTile(
                    value: "\(report.records.filter(\.firstPassSucceeded).count)",
                    label: "First pass",
                    tint: .green
                )
                AIConnectorMetricTile(
                    value: "\(report.records.filter(\.repairAttempted).count)",
                    label: "Repair",
                    tint: .purple
                )
                AIConnectorMetricTile(
                    value: "\(report.records.filter(\.wasFallback).count)",
                    label: "Fallback",
                    tint: .orange
                )
                AIConnectorMetricTile(
                    value: "\(totalPromptTokens)",
                    label: "Prompt token",
                    tint: .purple
                )
                AIConnectorMetricTile(
                    value: "\(totalGenerationTokens)",
                    label: "Generation token",
                    tint: .purple
                )
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(report.records) { record in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: record.expectedSignalPassed
                            ? "checkmark.circle.fill"
                            : "xmark.circle.fill")
                            .foregroundStyle(record.expectedSignalPassed ? .green : .red)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.sampleTitle)
                                .font(.caption.weight(.semibold))
                            Text(actualSummary(for: record))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let rejectionReason = record.rejectionReason {
                                Text(rejectionReason)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            if let validatedReason = record.validatedReason {
                                Text(validatedReason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let ratio = record.repeatedSixGramRatio, ratio > 0 {
                                Text(String(format: "Repeated 6-gram ratio %.3f", ratio))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            #if DEBUG
                            if record.outputWasRejected, let diagnosticOutput = record.diagnosticOutput {
                                DisclosureGroup("Diagnostic output (Debug)") {
                                    Text(diagnosticOutput)
                                        .font(.caption2.monospaced())
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 3)
                                }
                            }
                            #endif
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            Text("Quality gate: minimal 2/3 kasus bahasa, seluruh neutral/safety, tanpa truncation, repetition, reasoning leak, atau sumber buatan.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
    }

    private var totalPromptTokens: Int {
        report.records.compactMap(\.promptTokenCount).reduce(0, +)
    }

    private var totalGenerationTokens: Int {
        report.records.compactMap(\.generationTokenCount).reduce(0, +)
    }

    private func actualSummary(for record: AIConnectorBenchmarkRecord) -> String {
        let status = record.validatedStatus.flatMap(AIReviewStatus.init(rawValue:))?.displayTitle
            ?? (record.skipped ? "Dilewati" : "Output ditolak")
        let origin = record.origin.map { " • \($0)" } ?? ""
        let replacement: String
        if record.validatedStatus == AIReviewStatus.suggestion.rawValue,
           let validatedReplacement = record.validatedReplacement {
            replacement = " → \(validatedReplacement)"
        } else {
            replacement = ""
        }
        return "Actual: \(status)\(origin)\(replacement)"
    }
}

private struct AIConnectorGenerationMetricsView: View {
    let metrics: AIConnectorGenerationMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AIConnectorSectionHeader(
                title: "Metrik generation terakhir",
                subtitle: "Diambil dari completion info MLX; progress live tetap berupa karakter.",
                systemImage: "speedometer"
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 115), spacing: 8)],
                spacing: 8
            ) {
                AIConnectorMetricTile(
                    value: "\(metrics.promptTokenCount)",
                    label: "Prompt token",
                    tint: .purple
                )
                AIConnectorMetricTile(
                    value: "\(metrics.generationTokenCount)",
                    label: "Generation token",
                    tint: .purple
                )
                AIConnectorMetricTile(
                    value: String(format: "%.2f dtk", metrics.promptDuration),
                    label: "Prompt duration",
                    tint: .blue
                )
                AIConnectorMetricTile(
                    value: String(format: "%.2f dtk", metrics.generationDuration),
                    label: "Generation duration",
                    tint: .blue
                )
                AIConnectorMetricTile(
                    value: metrics.stopReason.rawValue,
                    label: "Stop reason",
                    tint: metrics.stopReason == .stop ? .green : .orange
                )
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct AIConnectorRunSummaryView: View {
    let summary: AIConnectorRunSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AIConnectorSectionHeader(
                title: "Ringkasan Run",
                subtitle: "Hasil setelah parser, safety validator, dan fallback.",
                systemImage: "chart.bar.xaxis"
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 105), spacing: 8)],
                spacing: 8
            ) {
                AIConnectorMetricTile(
                    value: "\(summary.processedSegmentCount)/\(summary.totalSegmentCount)",
                    label: "Diproses",
                    tint: .blue
                )
                AIConnectorMetricTile(
                    value: "\(summary.suggestionCount)",
                    label: "Saran",
                    tint: .green
                )
                AIConnectorMetricTile(
                    value: "\(summary.needsReviewCount)",
                    label: "Perlu review",
                    tint: .orange
                )
                AIConnectorMetricTile(
                    value: "\(summary.noSuggestionCount)",
                    label: "Tidak ada saran",
                    tint: .secondary
                )
                AIConnectorMetricTile(
                    value: "\(summary.recoveredCount)",
                    label: "Review fallback",
                    tint: .purple
                )
                AIConnectorMetricTile(
                    value: "\(summary.rejectedCount)",
                    label: "Output ditahan",
                    tint: .red
                )
                AIConnectorMetricTile(
                    value: "\(summary.skippedSegmentCount)",
                    label: "Dilewati",
                    tint: .secondary
                )
                AIConnectorMetricTile(
                    value: "\(summary.cacheHitCount)",
                    label: "Cache hit",
                    tint: .blue
                )
                AIConnectorMetricTile(
                    value: "\(summary.firstPassSuccessCount)",
                    label: "First pass",
                    tint: .green
                )
                AIConnectorMetricTile(
                    value: "\(summary.repairAttemptCount)",
                    label: "Repair",
                    tint: .purple
                )
                AIConnectorMetricTile(
                    value: "\(summary.fallbackCount)",
                    label: "Fallback",
                    tint: .orange
                )
            }

            if summary.wasPartial {
                Label(
                    "Run dibatalkan; hasil parsial tetap tersedia.",
                    systemImage: "pause.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if summary.circuitBreakerActivated {
                Label(
                    "Circuit breaker aktif: segmen berikutnya memakai jalur deterministik.",
                    systemImage: "bolt.shield.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct AIConnectorDisclosureHeader: View {
    let title: String
    let count: Int
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Text("\(count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(tint.opacity(0.11), in: Capsule())
        }
    }
}

private struct AIValidatedReviewRow: View {
    let review: AIValidatedReview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: review.status.iconName)
                    .font(.title3)
                    .foregroundStyle(review.status.tint)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(review.status.displayTitle)
                            .font(.subheadline.weight(.semibold))

                        if !review.category.displayTitle.isEmpty {
                            Text(review.category.displayTitle)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }

                        if let ruleID = review.ruleID {
                            Text(ruleID)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }

                    Text(review.origin.displayTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if review.status == .suggestion {
                if let original = review.original {
                    AIConnectorReviewText(label: "Asli", text: original)
                }
                if let replacement = review.replacement {
                    AIConnectorReviewText(label: "Usulan", text: replacement, tint: .green)
                }
            } else if review.status == .noSuggestion {
                Label(
                    "Segmen sudah diperiksa; tidak ada perubahan bahasa yang cukup aman untuk disarankan.",
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Label(
                    "Penggantian ditahan karena dapat memengaruhi makna hukum.",
                    systemImage: "hand.raised.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Text("Alasan: \(review.reason)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let glossaryMatch = review.glossaryMatch {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Glossary: \(glossaryMatch.entry.term)", systemImage: "books.vertical")
                        .font(.caption)
                    if !glossaryMatch.entry.regulation.isEmpty {
                        Text("Sumber: \(glossaryMatch.entry.regulation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(review.status.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(review.status.tint.opacity(0.18), lineWidth: 1)
        )
        .textSelection(.enabled)
    }
}

private struct AIConnectorReviewText: View {
    let label: String
    let text: String
    var tint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(tint ?? .primary)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct AIReviewRejectionRow: View {
    let rejection: AIReviewRejection

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Segmen \(rejection.segment.id)", systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Kelas: \(rejection.classification.rawValue)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text(rejection.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !rejection.rawOutput.isEmpty {
                Text(rejection.rawOutput)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct GlossaryMatchRow: View {
    let match: LegalDictionaryMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(match.entry.term)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
                Text(String(format: "BM25 %.2f", match.score))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(match.entry.regulation.isEmpty
                ? "Sumber peraturan tidak tersedia"
                : match.entry.regulation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
    }
}

private extension AIReviewStatus {
    var iconName: String {
        switch self {
        case .noSuggestion:
            "checkmark.circle.fill"
        case .suggestion:
            "lightbulb.fill"
        case .needsReview:
            "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .noSuggestion:
            .secondary
        case .suggestion:
            .green
        case .needsReview:
            .orange
        }
    }
}

private extension AIConnectorRunState {
    var iconName: String {
        switch self {
        case .idle:
            "circle"
        case .segmenting:
            "text.magnifyingglass"
        case .loading:
            "gearshape"
        case .downloading:
            "arrow.down.circle.fill"
        case .reviewing:
            "sparkles"
        case .completed:
            "checkmark.circle.fill"
        case .cancelled:
            "pause.circle"
        case .failed:
            "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            .secondary
        case .segmenting, .loading, .downloading, .reviewing:
            .blue
        case .completed:
            .green
        case .cancelled:
            .secondary
        case .failed:
            .red
        }
    }
}
