#if DEBUG
import AppKit
import CryptoKit
import Foundation

/// Errors raised by the Debug-only Phase 8 export surfaces.
nonisolated enum AIConnectorQualityExportError: LocalizedError, Equatable, Sendable {
    case cancelled
    case encodingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Ekspor dibatalkan."
        case .encodingFailed:
            "Report quality gate tidak dapat diserialisasi."
        case .writeFailed:
            "Report quality gate tidak dapat ditulis secara atomic."
        }
    }
}

nonisolated enum AIConnectorQualitySafeJSONExporter {
    static func defaultFileName(now: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        return "amt-phase8-quality-gate-\(timestamp).json"
    }

    static func encode(_ report: AIConnectorQualityEvaluationReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(report)
        } catch {
            throw AIConnectorQualityExportError.encodingFailed
        }
    }

    static func write(
        _ report: AIConnectorQualityEvaluationReport,
        to destination: URL
    ) throws -> URL {
        let data = try encode(report)
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).staging-\(UUID().uuidString)"
        )
        do {
            try data.write(to: staging, options: [.atomic])
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: destination)
            }
            return destination
        } catch {
            try? fileManager.removeItem(at: staging)
            throw AIConnectorQualityExportError.writeFailed
        }
    }
}

@MainActor
enum AIConnectorQualityReviewPackagePresenter {
    static func export(
        fixtures: [AIConnectorQualityFixture],
        reviews: [AIConnectorLawyerReviewRecord],
        now: Date = Date()
    ) -> Result<URL, AIConnectorQualityPackageError> {
        let panel = NSSavePanel()
        panel.title = "Ekspor Paket Review Lawyer"
        panel.message = "Paket ini berisi teks fixture sintetis dan dapat dibagikan untuk review lokal."
        panel.nameFieldStringValue = "amt-phase8-lawyer-review.amtquality"
        panel.canCreateDirectories = true
        panel.showsTagField = false
        guard panel.runModal() == .OK, let destination = panel.url else {
            return .failure(.cancelled)
        }

        do {
            let package = try AIConnectorQualityReviewPackageService.makePackage(
                fixtures: fixtures,
                reviews: reviews,
                now: now
            )
            return .success(try AIConnectorQualityReviewPackageService.export(package, to: destination))
        } catch let error as AIConnectorQualityPackageError {
            return .failure(error)
        } catch {
            return .failure(.writeFailed)
        }
    }

    static func `import`() -> Result<AIConnectorQualityReviewPackage, AIConnectorQualityPackageError> {
        let panel = NSOpenPanel()
        panel.title = "Impor Keputusan Review Lawyer"
        panel.message = "Pilih folder paket .amtquality yang sudah ditinjau."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let directory = panel.url else {
            return .failure(.cancelled)
        }

        do {
            return .success(try AIConnectorQualityReviewPackageService.load(from: directory))
        } catch let error as AIConnectorQualityPackageError {
            return .failure(error)
        } catch {
            return .failure(.invalidManifest)
        }
    }
}

nonisolated enum AIConnectorQualityCandidateManifestFactory {
    static let pipelineVersion = "phase8-quality-gate-v1"

    static func make(
        fixtures: [AIConnectorQualityFixture],
        policy: AIConnectorQualityPolicy,
        corpusVersion: String,
        modelVariants: [AIConnectorModelVariant] = AIConnectorModelVariant.allCases,
        sourceRevision: String = "local-dirty"
    ) -> AIConnectorQualityCandidateManifest {
        AIConnectorQualityCandidateManifest(
            candidateID: "amt-phase8-\(UUID().uuidString)",
            sourceRevision: sourceRevision,
            pipelineVersion: pipelineVersion,
            rulePackVersion: AIConnectorRuleStore.currentVersion,
            corpusVersion: corpusVersion,
            modelVariants: modelVariants.map { "\($0.rawValue)@\($0.revision)" }.sorted(),
            promptVersions: [
                QwenSuggestionService.promptVersion,
                QwenSuggestionService.outputSchemaVersion,
                QwenSuggestionService.candidatePromptVersion,
                QwenSuggestionService.candidateOutputSchemaVersion,
                QwenSuggestionService.definitionPromptVersion,
                QwenSuggestionService.definitionOutputSchemaVersion,
                QwenSuggestionService.contextPromptVersion,
                QwenSuggestionService.contextOutputSchemaVersion,
                QwenSuggestionService.riskPromptVersion,
                QwenSuggestionService.riskOutputSchemaVersion,
                QwenSuggestionService.definitionResolutionPromptVersion,
                QwenSuggestionService.definitionResolutionOutputSchemaVersion
            ].sorted(),
            fixtureCatalogVersion: AIConnectorQualityFixtureCatalog.version,
            fixtureManifestDigest: AIConnectorQualityReviewPackageService.fixtureManifestDigest(fixtures),
            policyID: policy.policyID,
            policyRevision: policy.revision,
            worktreeDirty: sourceRevision == "local-dirty"
        )
    }
}
#endif
