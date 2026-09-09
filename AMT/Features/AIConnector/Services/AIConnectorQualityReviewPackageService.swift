#if DEBUG
import CryptoKit
import Foundation

nonisolated enum AIConnectorQualityReviewPackageService {
    static let manifestFileName = "manifest.json"
    static let fixturesFileName = "fixtures.json"
    static let reviewsFileName = "reviews.json"
    static let guideFileName = "review-guide.md"

    static func makePackage(
        fixtures: [AIConnectorQualityFixture],
        reviews: [AIConnectorLawyerReviewRecord] = [],
        now: Date = Date()
    ) throws -> AIConnectorQualityReviewPackage {
        try validateFixtureSet(fixtures)
        let orderedFixtures = fixtures.sorted { $0.id < $1.id }
        let guide = reviewGuide(for: orderedFixtures)
        let manifest = AIConnectorQualityReviewPackageManifest(
            schemaVersion: AIConnectorQualityReviewPackageManifest.schemaVersion,
            packageID: UUID(),
            generatedAt: now,
            fixtureCatalogVersion: AIConnectorQualityFixtureCatalog.version,
            fixtureCount: orderedFixtures.count,
            fixtureJSONDigest: digest(orderedFixtures),
            reviewGuideDigest: digest(guide),
            includedFiles: [manifestFileName, fixturesFileName, reviewsFileName, guideFileName]
        )
        let package = AIConnectorQualityReviewPackage(
            manifest: manifest,
            fixtures: orderedFixtures,
            reviews: reviews.sorted { $0.fixtureID < $1.fixtureID },
            reviewGuideMarkdown: guide
        )
        try validate(package)
        return package
    }

    static func validate(_ package: AIConnectorQualityReviewPackage) throws {
        guard package.manifest.schemaVersion == AIConnectorQualityReviewPackageManifest.schemaVersion else {
            throw AIConnectorQualityPackageError.invalidSchema
        }
        try validateFixtureSet(package.fixtures)
        guard package.manifest.fixtureCatalogVersion == AIConnectorQualityFixtureCatalog.version,
              package.manifest.fixtureCount == package.fixtures.count,
              package.manifest.fixtureJSONDigest == digest(package.fixtures),
              package.manifest.reviewGuideDigest == digest(package.reviewGuideMarkdown),
              Set(package.manifest.includedFiles) == Set([
                  manifestFileName,
                  fixturesFileName,
                  reviewsFileName,
                  guideFileName
              ]) else {
            throw AIConnectorQualityPackageError.invalidManifest
        }

        var seenReviewIDs = Set<String>()
        let fixtureByID = Dictionary(uniqueKeysWithValues: package.fixtures.map { ($0.id, $0) })
        for review in package.reviews {
            guard seenReviewIDs.insert(review.fixtureID).inserted else {
                throw AIConnectorQualityPackageError.invalidManifest
            }
            guard let fixture = fixtureByID[review.fixtureID] else {
                throw AIConnectorQualityPackageError.unknownReviewFixture(review.fixtureID)
            }
            guard fixture.revision == review.fixtureRevision,
                  fixture.fixtureDigest == review.fixtureDigest else {
                throw AIConnectorQualityPackageError.staleReview(review.fixtureID)
            }
        }
    }

    static func export(
        _ package: AIConnectorQualityReviewPackage,
        to destination: URL
    ) throws -> URL {
        try validate(package)
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).staging-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            try writeJSON(package.manifest, to: staging.appendingPathComponent(manifestFileName))
            try writeJSON(package.fixtures, to: staging.appendingPathComponent(fixturesFileName))
            try writeJSON(package.reviews, to: staging.appendingPathComponent(reviewsFileName))
            guard let guideData = package.reviewGuideMarkdown.data(using: .utf8) else {
                throw AIConnectorQualityPackageError.encodingFailed
            }
            try guideData.write(
                to: staging.appendingPathComponent(guideFileName),
                options: [.atomic]
            )
            if fileManager.fileExists(atPath: destination.path) {
                throw AIConnectorQualityPackageError.writeFailed
            }
            try fileManager.moveItem(at: staging, to: destination)
            return destination
        } catch let error as AIConnectorQualityPackageError {
            try? fileManager.removeItem(at: staging)
            throw error
        } catch {
            try? fileManager.removeItem(at: staging)
            throw AIConnectorQualityPackageError.writeFailed
        }
    }

    static func load(from directory: URL) throws -> AIConnectorQualityReviewPackage {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw AIConnectorQualityPackageError.invalidDirectory
        }

        let manifest: AIConnectorQualityReviewPackageManifest = try readJSON(
            from: directory.appendingPathComponent(manifestFileName)
        )
        let fixtures: [AIConnectorQualityFixture] = try readJSON(
            from: directory.appendingPathComponent(fixturesFileName)
        )
        let reviews: [AIConnectorLawyerReviewRecord] = try readJSON(
            from: directory.appendingPathComponent(reviewsFileName)
        )
        let guideURL = directory.appendingPathComponent(guideFileName)
        guard FileManager.default.fileExists(atPath: guideURL.path) else {
            throw AIConnectorQualityPackageError.missingFile(guideFileName)
        }
        let guide: String
        do {
            guide = try String(contentsOf: guideURL, encoding: .utf8)
        } catch {
            throw AIConnectorQualityPackageError.invalidManifest
        }
        let package = AIConnectorQualityReviewPackage(
            manifest: manifest,
            fixtures: fixtures,
            reviews: reviews,
            reviewGuideMarkdown: guide
        )
        try validate(package)
        return package
    }

    static func fixtureManifestDigest(_ fixtures: [AIConnectorQualityFixture]) -> String {
        digest(fixtures.sorted { $0.id < $1.id }.map { $0.fixtureDigest })
    }

    private static func validateFixtureSet(_ fixtures: [AIConnectorQualityFixture]) throws {
        var IDs = Set<String>()
        var splitByScenario: [String: AIConnectorQualityFixtureSplit] = [:]
        for fixture in fixtures {
            guard !fixture.id.isEmpty,
                  !fixture.scenarioID.isEmpty,
                  !fixture.text.isEmpty,
                  fixture.revision > 0,
                  fixture.provenance == .synthetic
                      || (fixture.rightsDeclared && fixture.anonymizationChecked),
                  fixture.expected.findings.allSatisfy({ $0.occurrence >= 0 }) else {
                throw AIConnectorQualityPackageError.invalidFixture(fixture.id)
            }
            guard IDs.insert(fixture.id).inserted else {
                throw AIConnectorQualityPackageError.duplicateFixtureID(fixture.id)
            }
            if let existingSplit = splitByScenario[fixture.scenarioID], existingSplit != fixture.split {
                throw AIConnectorQualityPackageError.invalidFixture(fixture.id)
            }
            splitByScenario[fixture.scenarioID] = fixture.split
            let sourceIDs = Set(fixture.sources.map(\.id))
            guard sourceIDs.count == fixture.sources.count,
                  fixture.expected.requiredSourceIDs.count == Set(fixture.expected.requiredSourceIDs).count,
                  fixture.expected.requiredSourceIDs.allSatisfy(sourceIDs.contains),
                  fixture.expected.findings.allSatisfy({ finding in
                      finding.sourceID == nil
                          || fixture.sources.contains {
                              $0.id == finding.sourceID || $0.corpusEntryID == finding.sourceID
                          }
                  }) else {
                throw AIConnectorQualityPackageError.invalidFixture(fixture.id)
            }
        }
    }

    private static func reviewGuide(for fixtures: [AIConnectorQualityFixture]) -> String {
        var lines = [
            "# AMT Phase 8 — Review Fixture Lawyer",
            "",
            "Paket ini berisi fixture sintetis untuk menilai kualitas fitur Document.",
            "Tinjau teks, expected outcome, sumber, applicability, hard-negative, dan safety.",
            "Setujui hanya fixture yang seluruh ekspektasinya dapat dipertanggungjawabkan.",
            ""
        ]
        for fixture in fixtures {
            lines.append("## \(fixture.id) (revisi \(fixture.revision))")
            lines.append("")
            lines.append("- Kategori: \(fixture.category.rawValue)")
            lines.append("- Split: \(fixture.split.rawValue)")
            lines.append("- Provenance: \(fixture.provenance.rawValue)")
            lines.append("- Hak penggunaan dinyatakan: \(fixture.rightsDeclared)")
            lines.append("- Pemeriksaan anonimisasi: \(fixture.anonymizationChecked)")
            lines.append("- Pertanyaan: \(fixture.question)")
            lines.append("")
            lines.append("### Teks")
            lines.append("")
            lines.append("```text")
            lines.append(fixture.text)
            lines.append("```")
            lines.append("")
            lines.append("### Expected")
            lines.append("")
            if fixture.expected.noChange {
                lines.append("- no-change: true")
            }
            for finding in fixture.expected.findings {
                let original = finding.original ?? "-"
                let replacement = finding.replacement ?? "-"
                lines.append("- occurrence \(finding.occurrence), category \(finding.category.rawValue), status \(finding.status), original \(original), replacement \(replacement)")
            }
            if !fixture.sources.isEmpty {
                lines.append("")
                lines.append("### Sources")
                lines.append("")
                for source in fixture.sources {
                    let corpusID = source.corpusEntryID ?? "-"
                    let referenceID = source.referenceID ?? "-"
                    let evidenceID = source.evidenceID ?? "-"
                    lines.append("- \(source.id): corpus \(corpusID), reference \(referenceID), evidence \(evidenceID), applicability \(source.applicabilityStatus), verified \(source.verified), actionable \(source.isActionable)")
                }
            }
            lines.append("")
            lines.append("### Review questions")
            lines.append("")
            lines.append("- Apakah kategori dan occurrence sudah tepat?")
            lines.append("- Apakah replacement dan status read-only/actionable sudah tepat?")
            lines.append("- Apakah sumber, evidence, dan applicability dapat diverifikasi?")
            lines.append("- Jika hard-negative, apakah hasil yang diharapkan benar-benar no-change?")
            lines.append("- Apakah penerapan hasil berpotensi menimbulkan safety violation?")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(value).write(to: url, options: [.atomic])
        } catch {
            throw AIConnectorQualityPackageError.writeFailed
        }
    }

    private static func readJSON<T: Decodable>(from url: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AIConnectorQualityPackageError.missingFile(url.lastPathComponent)
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: Data(contentsOf: url))
        } catch let error as AIConnectorQualityPackageError {
            throw error
        } catch {
            throw AIConnectorQualityPackageError.invalidSchema
        }
    }

    private static func digest<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data()
        return data.sha256Hex
    }
}

@MainActor
final class AIConnectorQualityFixtureStore {
    private(set) var fixtures: [AIConnectorQualityFixture]
    private(set) var reviews: [String: AIConnectorLawyerReviewRecord]

    init(
        fixtures: [AIConnectorQualityFixture] = AIConnectorQualityFixtureCatalog.fixtures,
        reviews: [AIConnectorLawyerReviewRecord] = []
    ) {
        self.fixtures = fixtures.sorted { $0.id < $1.id }
        self.reviews = Dictionary(uniqueKeysWithValues: reviews.map { ($0.fixtureID, $0) })
    }

    var approvedFixtureCount: Int {
        fixtures.filter { reviews[$0.id]?.isApproved == true }.count
    }

    func apply(_ package: AIConnectorQualityReviewPackage) throws -> AIConnectorQualityReviewPackageResult {
        try AIConnectorQualityReviewPackageService.validate(package)
        var nextFixtures = Dictionary(uniqueKeysWithValues: fixtures.map { ($0.id, $0) })
        var nextReviews = reviews
        for fixture in package.fixtures {
            if let previous = nextFixtures[fixture.id],
               previous.revision != fixture.revision || previous.fixtureDigest != fixture.fixtureDigest {
                nextReviews.removeValue(forKey: fixture.id)
            }
            nextFixtures[fixture.id] = fixture
        }
        for review in package.reviews {
            nextReviews[review.fixtureID] = review
        }
        fixtures = nextFixtures.values.sorted { $0.id < $1.id }
        reviews = nextReviews
        return AIConnectorQualityReviewPackageResult(
            fixtures: fixtures,
            reviews: Array(reviews.values).sorted { $0.fixtureID < $1.fixtureID }
        )
    }

    func review(for fixtureID: String) -> AIConnectorLawyerReviewRecord? {
        reviews[fixtureID]
    }
}

private extension Data {
    nonisolated var sha256Hex: String {
        CryptoKit.SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
