#if DEBUG
import AppKit
import Foundation

enum AIConnectorObservationExportError: LocalizedError, Equatable, Sendable {
    case cancelled
    case encodingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Ekspor dibatalkan."
        case .encodingFailed:
            "Report Phase 0 tidak dapat diserialisasi."
        case .writeFailed:
            "Report Phase 0 tidak dapat ditulis ke lokasi yang dipilih."
        }
    }
}

enum AIConnectorPhaseTwoComparisonExportError: LocalizedError, Equatable, Sendable {
    case cancelled
    case encodingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Ekspor perbandingan Phase 2 dibatalkan."
        case .encodingFailed:
            "Report perbandingan Phase 2 tidak dapat diserialisasi."
        case .writeFailed:
            "Report perbandingan Phase 2 tidak dapat ditulis ke lokasi yang dipilih."
        }
    }
}

/// Explicit, user-triggered exporter for the privacy-safe Phase 0 DTO.
@MainActor
enum AIConnectorObservationExporter {
    static func encode(
        _ report: AIConnectorBaselineSuiteReport
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(report)
        } catch {
            throw AIConnectorObservationExportError.encodingFailed
        }
    }

    @discardableResult
    static func write(
        _ report: AIConnectorBaselineSuiteReport,
        to url: URL
    ) throws -> URL {
        let data = try encode(report)
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            throw AIConnectorObservationExportError.writeFailed
        }
    }

    static func defaultFileName(
        at date: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "amt-phase0-baseline-\(formatter.string(from: date)).json"
    }

    static func presentSavePanel(
        for report: AIConnectorBaselineSuiteReport,
        completion: @escaping (Result<URL, AIConnectorObservationExportError>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = "Ekspor Phase 0"
        panel.message = "Simpan report observability yang sudah disanitasi."
        panel.nameFieldStringValue = defaultFileName()
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(.failure(.cancelled))
                return
            }
            do {
                try write(report, to: url)
                completion(.success(url))
            } catch let error as AIConnectorObservationExportError {
                completion(.failure(error))
            } catch {
                completion(.failure(.writeFailed))
            }
        }
    }
}

/// Separate exporter so Phase 2 cannot accidentally encode the legacy
/// benchmark records that contain fixture text and diagnostic output.
@MainActor
enum AIConnectorPhaseTwoComparisonExporter {
    static func encode(
        _ report: AIConnectorPhaseTwoComparisonReport
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(report)
        } catch {
            throw AIConnectorPhaseTwoComparisonExportError.encodingFailed
        }
    }

    @discardableResult
    static func write(
        _ report: AIConnectorPhaseTwoComparisonReport,
        to url: URL
    ) throws -> URL {
        let data = try encode(report)
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            throw AIConnectorPhaseTwoComparisonExportError.writeFailed
        }
    }

    static func defaultFileName(
        at date: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "amt-phase2-comparison-\(formatter.string(from: date)).json"
    }

    static func presentSavePanel(
        for report: AIConnectorPhaseTwoComparisonReport,
        completion: @escaping (Result<URL, AIConnectorPhaseTwoComparisonExportError>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = "Ekspor perbandingan Phase 2"
        panel.message = "Simpan report perbandingan yang sudah disanitasi."
        panel.nameFieldStringValue = defaultFileName()
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(.failure(.cancelled))
                return
            }
            do {
                try write(report, to: url)
                completion(.success(url))
            } catch let error as AIConnectorPhaseTwoComparisonExportError {
                completion(.failure(error))
            } catch {
                completion(.failure(.writeFailed))
            }
        }
    }
}
#endif
