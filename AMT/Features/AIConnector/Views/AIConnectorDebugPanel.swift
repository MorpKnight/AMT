import Foundation
import SwiftUI

struct AIConnectorDebugPanel: View {
    let documentText: String

    @Bindable var viewModel: AIConnectorViewModel

    var body: some View {
        AIConnectorNativeDebugContent(
            documentText: documentText,
            viewModel: viewModel
        )
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

private struct AIConnectorNativeDebugContent: View {
    let documentText: String

    @Bindable var viewModel: AIConnectorViewModel

    private var actionableReviews: [AIValidatedReview] {
        viewModel.validatedReviews.filter { review in
            guard review.status == .suggestion,
                  let original = review.original,
                  let replacement = review.replacement else {
                return false
            }

            return !original.isEmpty
                && !replacement.isEmpty
                && original != replacement
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggestion")
                        .font(.title2.weight(.semibold))
                    Text("Periksa ejaan, tata bahasa, dan istilah tanpa mengubah dokumen secara otomatis.")
                        .foregroundStyle(.secondary)
                }

                Label(
                    "Eksperimental — bukan nasihat hukum",
                    systemImage: "info.circle"
                )
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }

            Section("Sumber") {
                Picker("Dokumen", selection: $viewModel.inputSource) {
                    ForEach(AIConnectorInputSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }

                if viewModel.inputSource == .dummy {
                    Picker("Contoh", selection: $viewModel.selectedSampleID) {
                        ForEach(AIConnectorSample.samples) { sample in
                            Text(sample.title).tag(sample.id)
                        }
                    }

                    DisclosureGroup("Sinyal yang diharapkan") {
                        Text(viewModel.selectedSample.expectedSignal)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                } else {
                    LabeledContent("Panjang") {
                        Text("\(documentText.count) karakter")
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Preview") {
                    Text(viewModel.inputPreview(documentText: documentText))
                        .font(.callout)
                        .lineLimit(6)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.inputWasTruncated(documentText: documentText) {
                    Label(
                        "Preview menampilkan 4.000 karakter pertama. Analisis tetap memakai seluruh dokumen.",
                        systemImage: "scissors"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Pengaturan") {
                Picker("Strategi", selection: $viewModel.reviewMode) {
                    ForEach(AIConnectorReviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if viewModel.reviewMode.usesModel {
                    Picker("Model", selection: $viewModel.modelVariant) {
                        ForEach(AIConnectorModelVariant.allCases) { model in
                            Text(model.title).tag(model)
                        }
                    }

                    LabeledContent("Versi") {
                        Text("\(viewModel.modelVariant.downloadEstimate) · rev \(viewModel.modelVariant.shortRevision)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Picker("Profil", selection: $viewModel.generationProfilePreset) {
                        ForEach(AIConnectorGenerationProfilePreset.allCases) { profile in
                            Text(profile.title).tag(profile)
                        }
                    }

                    Toggle("Mode thinking (eksperimental)", isOn: $viewModel.thinkingEnabled)
                        .help("Reasoning internal tidak ditampilkan.")
                }

                Text(viewModel.reviewMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(viewModel.isRunning)

            Section("Review") {
                HStack(spacing: 8) {
                    if viewModel.isRunning {
                        Button(role: .cancel) {
                            viewModel.cancel()
                        } label: {
                            Label("Batalkan", systemImage: "stop")
                        }
                        .keyboardShortcut(.cancelAction)
                    } else {
                        Button {
                            viewModel.run(documentText: documentText)
                        } label: {
                            Label("Mulai review", systemImage: "text.magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(!viewModel.canRun(documentText: documentText))

                        if case .failed = viewModel.state {
                            Button {
                                viewModel.run(documentText: documentText)
                            } label: {
                                Label("Coba lagi", systemImage: "arrow.clockwise")
                            }
                        }
                    }

                    Spacer(minLength: 0)
                    AIConnectorNativeStatusLine(state: viewModel.state)
                }

                AIConnectorNativeProgressView(
                    state: viewModel.state,
                    generationProgress: viewModel.generationProgress
                )

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            if let summary = viewModel.runSummary {
                Section("Ringkasan") {
                    AIConnectorNativeRunSummaryView(summary: summary)
                }
            }

            if !actionableReviews.isEmpty {
                Section("Rekomendasi") {
                    ForEach(actionableReviews) { review in
                        AIConnectorNativeValidatedReviewRow(review: review)
                    }
                }
            }

            #if DEBUG
            if !viewModel.rejectedReviews.isEmpty {
                Section("Output ditolak") {
                    ForEach(viewModel.rejectedReviews) { rejection in
                        AIConnectorNativeRejectionRow(rejection: rejection)
                    }
                }
            }
            #endif

            if !viewModel.output.isEmpty {
                Section("Output rekomendasi") {
                    Text(viewModel.output)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            Section {
                DisclosureGroup("Detail debug") {
                    AIConnectorNativeDebugDetails(viewModel: viewModel)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
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
        .onChange(of: viewModel.generationProfilePreset) { _, _ in
            viewModel.resetInputMetadata()
        }
        .onChange(of: documentText) { _, _ in
            viewModel.resetInputMetadata()
        }
    }
}

private struct AIConnectorNativeDebugDetails: View {
    @Bindable var viewModel: AIConnectorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                viewModel.runBenchmark()
            } label: {
                Label(
                    viewModel.reviewMode == .deterministic
                        ? "Uji baseline"
                        : "Jalankan benchmark fixture",
                    systemImage: "checklist"
                )
            }
            .disabled(!viewModel.canRunBenchmark)
            .help("Jalankan benchmark tanpa mengubah dokumen.")

            if let segmentation = viewModel.segmentationResult {
                LabeledContent("Segmentasi") {
                    Text("\(segmentation.segments.count) segmen · \(segmentation.headingCount) heading")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Batas") {
                    Text("\(segmentation.tooLongSegmentCount) terlalu panjang · \(viewModel.skippedSegmentCount) dilewati")
                        .foregroundStyle(.secondary)
                }
                if !viewModel.queueBatchSizes.isEmpty {
                    LabeledContent("Batch") {
                        Text(viewModel.queueBatchSizes.map(String.init).joined(separator: " / ") + " · serial")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Belum ada hasil diagnostik.")
                    .foregroundStyle(.secondary)
            }

            if !viewModel.currentSegmentPreview.isEmpty {
                DisclosureGroup("Target saat ini") {
                    Text(viewModel.currentSegmentPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
            }

            if !viewModel.currentGlossaryMatches.isEmpty {
                DisclosureGroup("Kandidat glossary saat ini") {
                    ForEach(viewModel.currentGlossaryMatches) { match in
                        AIConnectorNativeGlossaryMatchRow(match: match)
                    }
                }
            }

            if !viewModel.glossarySnapshots.isEmpty {
                DisclosureGroup("Kandidat glossary hasil run") {
                    ForEach(viewModel.glossarySnapshots) { snapshot in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Segmen \(snapshot.segment.id)")
                                .font(.subheadline.weight(.semibold))
                            Text(snapshot.segment.targetText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                            ForEach(snapshot.matches) { match in
                                AIConnectorNativeGlossaryMatchRow(match: match)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if viewModel.currentQueueState != nil || !viewModel.queueBatchSizes.isEmpty {
                DisclosureGroup("Queue") {
                    if let state = viewModel.currentQueueState {
                        LabeledContent("State") {
                            Text(state.rawValue)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let batchIndex = viewModel.currentBatchIndex,
                       let batchSize = viewModel.currentBatchSize {
                        LabeledContent("Batch aktif") {
                            Text("\(batchIndex) dari \(viewModel.queueBatchSizes.count) · \(batchSize) item")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !viewModel.currentCandidates.isEmpty || !viewModel.currentCandidateDecisions.isEmpty {
                DisclosureGroup("Kandidat dan keputusan") {
                    ForEach(viewModel.currentCandidates) { candidate in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(candidate.id)
                                    .font(.body.monospaced().weight(.semibold))
                                Text(candidate.category.displayTitle)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                if let decision = viewModel.currentCandidateDecisions.first(where: {
                                    $0.candidateID == candidate.id
                                }) {
                                    Text(decision.decision?.rawValue ?? "MODEL_FAILURE")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("\(candidate.original) → \(candidate.replacement)")
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if let evaluation = viewModel.fixtureEvaluation {
                DisclosureGroup("Fixture") {
                    LabeledContent("Status") {
                        Text(evaluation.passed ? "Lulus" : "Belum lulus")
                            .foregroundStyle(evaluation.passed ? .green : .orange)
                    }
                    Text(evaluation.sample.expectedSignal)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(evaluation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let benchmarkReport = viewModel.benchmarkReport {
                DisclosureGroup("Benchmark") {
                    AIConnectorNativeBenchmarkReportView(report: benchmarkReport)
                }
            } else if let benchmarkSummary = viewModel.benchmarkSummary {
                DisclosureGroup("Benchmark") {
                    AIConnectorNativeBenchmarkSummaryView(summary: benchmarkSummary)
                }
            }

            if let metrics = viewModel.latestGenerationMetrics {
                DisclosureGroup("Metrik generation") {
                    AIConnectorNativeGenerationMetricsView(metrics: metrics)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

private struct AIConnectorNativeStatusLine: View {
    let state: AIConnectorRunState

    var body: some View {
        Label(state.title, systemImage: state.iconName)
            .foregroundStyle(state.tint)
            .accessibilityValue(state.title)
    }
}

private struct AIConnectorNativeProgressView: View {
    let state: AIConnectorRunState
    let generationProgress: Int

    @ViewBuilder
    var body: some View {
        switch state {
        case let .downloading(progress):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                LabeledContent("Mengunduh model") {
                    Text("\(Int(progress * 100))%")
                        .monospacedDigit()
                }
            }
        case let .reviewing(current, total):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(current), total: Double(max(total, 1)))
                LabeledContent("Meninjau") {
                    Text("\(current) dari \(total)")
                        .monospacedDigit()
                }
                Text("\(generationProgress) karakter keluaran · hasil ditampilkan setelah pemeriksaan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .segmenting:
            ProgressView("Menyiapkan teks")
        case .loading:
            ProgressView("Memuat model")
        default:
            EmptyView()
        }
    }
}

private struct AIConnectorNativeRunSummaryView: View {
    let summary: AIConnectorRunSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Diproses") {
                Text("\(summary.processedSegmentCount) dari \(summary.totalSegmentCount)")
                    .monospacedDigit()
            }
            LabeledContent("Saran") {
                Text("\(summary.suggestionCount)")
                    .monospacedDigit()
            }
            LabeledContent("Perlu review") {
                Text("\(summary.needsReviewCount)")
                    .monospacedDigit()
            }
            LabeledContent("Ditahan") {
                Text("\(summary.rejectedCount)")
                    .monospacedDigit()
            }

            DisclosureGroup("Statistik lengkap") {
                LabeledContent("Tidak ada saran") {
                    Text("\(summary.noSuggestionCount)").monospacedDigit()
                }
                LabeledContent("Fallback") {
                    Text("\(summary.fallbackCount)").monospacedDigit()
                }
                LabeledContent("Cache hit") {
                    Text("\(summary.cacheHitCount)").monospacedDigit()
                }
                LabeledContent("First pass") {
                    Text("\(summary.firstPassSuccessCount)").monospacedDigit()
                }
                LabeledContent("Model call") {
                    Text("\(summary.modelCallCount)").monospacedDigit()
                }
                LabeledContent("Challenge") {
                    Text("\(summary.challengeCount)").monospacedDigit()
                }
            }

            if summary.wasPartial {
                Label("Run dibatalkan; hasil parsial tetap tersedia.", systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if summary.circuitBreakerActivated {
                Label("Jalur deterministik dipakai untuk segmen berikutnya.", systemImage: "bolt.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AIConnectorNativeValidatedReviewRow: View {
    let review: AIValidatedReview

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: review.status.iconName)
                    .foregroundStyle(review.status.tint)
                Text(review.category.displayTitle)
                    .font(.subheadline.weight(.semibold))
                Text(review.origin.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            if let original = review.original {
                LabeledContent("Asli") {
                    Text(original)
                        .strikethrough()
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let replacement = review.replacement {
                LabeledContent("Usulan") {
                    Text(replacement)
                        .foregroundStyle(.green)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Text("Alasan: \(review.reason)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if review.category == .terminology,
               let glossaryMatch = review.glossaryMatch {
                LabeledContent("Istilah hukum") {
                    Text(glossaryMatch.entry.term)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !glossaryMatch.entry.regulation.isEmpty {
                    LabeledContent("Peraturan") {
                        Text(glossaryMatch.entry.regulation)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !glossaryMatch.entry.regulationTitle.isEmpty {
                    LabeledContent("Judul") {
                        Text(glossaryMatch.entry.regulationTitle)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let sourceURL = glossaryMatch.entry.sourceURL {
                    LabeledContent("Sumber") {
                        Link("Buka sumber", destination: sourceURL)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AIConnectorNativeRejectionRow: View {
    let rejection: AIReviewRejection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Segmen \(rejection.segment.id)", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            LabeledContent("Kelas") {
                Text(rejection.classification.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(rejection.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if rejection.rawOutput.isEmpty {
                Text("Output mentah tidak tersedia.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                DisclosureGroup("Output mentah (Debug)") {
                    Text(rejection.rawOutput)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AIConnectorNativeGlossaryMatchRow: View {
    let match: LegalDictionaryMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(match.entry.term)
                    .font(.subheadline.weight(.semibold))
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
                .textSelection(.enabled)

            Label(
                match.entry.authority == .verified
                    ? "Dapat dipakai sebagai evidence"
                    : "Legacy — hanya diagnostik, belum menjadi rekomendasi",
                systemImage: match.entry.authority == .verified
                    ? "checkmark.seal"
                    : "lock.shield"
            )
            .font(.caption2)
            .foregroundStyle(match.entry.authority == .verified ? .green : .secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct AIConnectorNativeBenchmarkSummaryView: View {
    let summary: AIConnectorBenchmarkSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Hasil") {
                Text("\(summary.passedCount) dari \(summary.totalCount)")
                    .monospacedDigit()
            }
            LabeledContent("Durasi") {
                Text(String(format: "%.2f dtk", summary.duration))
                    .monospacedDigit()
            }
            ForEach(summary.evaluations) { evaluation in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: evaluation.passed
                        ? "checkmark.circle"
                        : "xmark.circle")
                        .foregroundStyle(evaluation.passed ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(evaluation.sample.title)
                            .font(.caption.weight(.semibold))
                        Text(evaluation.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct AIConnectorNativeBenchmarkReportView: View {
    let report: AIConnectorBenchmarkReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(qualityGateTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(qualityGateColor)
                Spacer(minLength: 0)
                Text("\(report.passedCount) dari \(report.totalCount)")
                    .monospacedDigit()
            }

            LabeledContent("Profil") {
                Text(report.generationProfile)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Durasi") {
                Text(String(format: "%.2f dtk", report.duration))
                    .monospacedDigit()
            }
            LabeledContent("Safety") {
                Text("\(report.qualityGate.safetyContainedCount) dari \(report.qualityGate.safetyTotal)")
                    .monospacedDigit()
            }
            LabeledContent("Utility akhir") {
                Text(report.qualityGate.utilityPassed ? "Lulus" : "Belum lulus")
                    .foregroundStyle(report.qualityGate.utilityPassed ? .green : .orange)
            }
            LabeledContent("Hasil asal model") {
                Text("\(report.qualityGate.modelOriginResultCount)")
                    .monospacedDigit()
            }
            LabeledContent("Fallback") {
                Text("\(report.qualityGate.fallbackCount)")
                    .monospacedDigit()
            }
            LabeledContent("Model call") {
                Text("\(report.records.reduce(0) { $0 + $1.modelCallCount })")
                    .monospacedDigit()
            }
            LabeledContent("Cache hit") {
                Text("\(report.records.filter(\.cacheHit).count)")
                    .monospacedDigit()
            }

            #if DEBUG
            if !report.candidateRecords.isEmpty {
                DisclosureGroup("Detail kandidat") {
                    ForEach(report.candidateRecords) { candidate in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(candidate.sampleTitle) · \(candidate.candidateID)")
                                .font(.caption.weight(.semibold))
                            Text("\(candidate.original) → \(candidate.replacement)")
                                .font(.caption)
                                .textSelection(.enabled)
                            Text("\(candidate.source.displayTitle) · \(candidate.decision?.rawValue ?? "MODEL_FAILURE")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            #endif
        }
    }

    private var qualityGateTitle: String {
        switch report.qualityGate.decision {
        case .go:
            "Model gate: GO"
        case .noGo:
            "Model gate: NO-GO"
        case .notApplicable:
            "Model gate: tidak berlaku"
        }
    }

    private var qualityGateColor: Color {
        switch report.qualityGate.decision {
        case .go:
            .green
        case .noGo:
            .orange
        case .notApplicable:
            .secondary
        }
    }
}

private struct AIConnectorNativeGenerationMetricsView: View {
    let metrics: AIConnectorGenerationMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Prompt") {
                Text("\(metrics.promptTokenCount) token · \(String(format: "%.2f dtk", metrics.promptDuration))")
                    .monospacedDigit()
            }
            LabeledContent("Keluaran") {
                Text("\(metrics.generationTokenCount) token · \(String(format: "%.2f dtk", metrics.generationDuration))")
                    .monospacedDigit()
            }
            LabeledContent("Stop reason") {
                Text(metrics.stopReason.rawValue)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
