#!/usr/bin/env xcrun swift

import Foundation

enum ValidationExit: Int32 {
    case pass = 0
    case notPassed = 1
    case invalidInput = 2
}

struct Arguments {
    let report: URL
    let policy: URL
    let manifest: URL

    init() throws {
        var values: [String: String] = [:]
        var index = 1
        while index < CommandLine.arguments.count {
            let argument = CommandLine.arguments[index]
            guard argument.hasPrefix("--"), index + 1 < CommandLine.arguments.count else {
                throw ValidationError.invalidArguments
            }
            values[String(argument.dropFirst(2))] = CommandLine.arguments[index + 1]
            index += 2
        }
        guard let report = values["report"],
              let policy = values["policy"],
              let manifest = values["manifest"] else {
            throw ValidationError.invalidArguments
        }
        self.report = URL(fileURLWithPath: report)
        self.policy = URL(fileURLWithPath: policy)
        self.manifest = URL(fileURLWithPath: manifest)
    }
}

enum ValidationError: Error {
    case invalidArguments
    case unreadable(URL)
    case invalidJSON(URL)
    case missing(String, URL)
    case mismatch(String)
}

func object(at url: URL) throws -> [String: Any] {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw ValidationError.unreadable(url)
    }
    do {
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let object = value as? [String: Any] else {
            throw ValidationError.invalidJSON(url)
        }
        return object
    } catch let error as ValidationError {
        throw error
    } catch {
        throw ValidationError.invalidJSON(url)
    }
}

func requiredString(_ key: String, from object: [String: Any], file: URL) throws -> String {
    guard let value = object[key] as? String, !value.isEmpty else {
        throw ValidationError.missing(key, file)
    }
    return value
}

func requiredInt(_ key: String, from object: [String: Any], file: URL) throws -> Int {
    guard let value = object[key] as? Int else {
        throw ValidationError.missing(key, file)
    }
    return value
}

func requiredBool(_ key: String, from object: [String: Any], file: URL) throws -> Bool {
    guard let value = object[key] as? Bool else {
        throw ValidationError.missing(key, file)
    }
    return value
}

func exitWith(_ code: ValidationExit, message: String) -> Never {
    FileHandle.standardError.write(Data("quality-gate: \(message)\n".utf8))
    Foundation.exit(code.rawValue)
}

do {
    let arguments = try Arguments()
    let report = try object(at: arguments.report)
    let policy = try object(at: arguments.policy)
    let manifest = try object(at: arguments.manifest)

    guard try requiredString("schemaVersion", from: report, file: arguments.report)
        == "phase8-quality-report-v1" else {
        throw ValidationError.mismatch("report schema")
    }
    guard try requiredString("schemaVersion", from: policy, file: arguments.policy)
        == "phase8-quality-policy-v1" else {
        throw ValidationError.mismatch("policy schema")
    }
    guard try requiredString("schemaVersion", from: manifest, file: arguments.manifest)
        == "phase8-quality-candidate-v1" else {
        throw ValidationError.mismatch("candidate manifest schema")
    }

    let reportPolicyID = try requiredString("policyID", from: report, file: arguments.report)
    let policyID = try requiredString("policyID", from: policy, file: arguments.policy)
    let manifestPolicyID = try requiredString("policyID", from: manifest, file: arguments.manifest)
    guard reportPolicyID == policyID, policyID == manifestPolicyID else {
        throw ValidationError.mismatch("policy ID")
    }

    let reportPolicyRevision = try requiredInt("policyRevision", from: report, file: arguments.report)
    let policyRevision = try requiredInt("revision", from: policy, file: arguments.policy)
    let manifestPolicyRevision = try requiredInt("policyRevision", from: manifest, file: arguments.manifest)
    guard reportPolicyRevision == policyRevision, policyRevision == manifestPolicyRevision else {
        throw ValidationError.mismatch("policy revision")
    }

    for key in ["fixtureCatalogVersion", "pipelineVersion", "rulePackVersion", "corpusVersion"] {
        let reportValue = try requiredString(key, from: report, file: arguments.report)
        let manifestValue = try requiredString(key, from: manifest, file: arguments.manifest)
        guard reportValue == manifestValue else {
            throw ValidationError.mismatch(key)
        }
    }

    let candidateDigest = try requiredString("candidateManifestDigest", from: report, file: arguments.report)
    guard candidateDigest.count == 64,
          candidateDigest.allSatisfy({ $0.isHexDigit }) else {
        throw ValidationError.mismatch("candidate manifest digest")
    }

    let status = try requiredString("overallStatus", from: report, file: arguments.report)
    guard ["pass", "fail", "insufficientEvidence"].contains(status) else {
        throw ValidationError.mismatch("overall status")
    }
    let terminalStatus = try requiredString("terminalStatus", from: report, file: arguments.report)
    guard terminalStatus == "completed" else {
        exitWith(.notPassed, message: "run belum lengkap")
    }

    let approved = try requiredBool("approved", from: policy, file: arguments.policy)
    let worktreeDirty = try requiredBool("worktreeDirty", from: manifest, file: arguments.manifest)
    guard approved, !worktreeDirty else {
        exitWith(.notPassed, message: approved ? "candidate berasal dari dirty worktree" : "policy belum disetujui")
    }

    let coverage = (report["approvedCoverageFraction"] as? NSNumber)?.doubleValue ?? 0
    let requiredCoverage = (policy["requiredCoverageFraction"] as? NSNumber)?.doubleValue ?? 1
    guard coverage >= requiredCoverage else {
        exitWith(.notPassed, message: "coverage fixture belum memenuhi policy")
    }

    switch status {
    case "pass":
        Foundation.exit(ValidationExit.pass.rawValue)
    case "fail":
        exitWith(.notPassed, message: "quality gate fail")
    default:
        exitWith(.notPassed, message: "bukti evaluasi belum cukup")
    }
} catch let error as ValidationError {
    exitWith(.invalidInput, message: String(describing: error))
} catch {
    exitWith(.invalidInput, message: error.localizedDescription)
}
