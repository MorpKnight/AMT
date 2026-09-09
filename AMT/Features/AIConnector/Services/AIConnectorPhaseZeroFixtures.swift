#if DEBUG
import Foundation

/// The Phase 0 fixture catalog is synthetic and deterministic. It is kept
/// separate from user documents and is intentionally not part of the export.
nonisolated enum AIConnectorPhaseZeroFixtureCatalog {
    static let fixtures: [AIConnectorPhaseZeroFixture] = {
        let dataPribadiDefinition = "Data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik"

        var result: [AIConnectorPhaseZeroFixture] = []

        let spellingCases: [(String, String, String)] = [
            ("memasukan", "memasukkan", "Memperbaiki ejaan imbuhan."),
            ("ditanda tangani", "ditandatangani", "Memperbaiki bentuk kata baku."),
            ("di simpan", "disimpan", "Memperbaiki pemisahan imbuhan.")
        ]
        for (caseIndex, spellingCase) in spellingCases.enumerated() {
            for variant in 1 ... 5 {
                let original = spellingCase.0
                let replacement = spellingCase.1
                result.append(
                    AIConnectorPhaseZeroFixture(
                        id: String(format: "p0-spelling-%02d", caseIndex * 5 + variant),
                        category: .spelling,
                        text: spellingText(
                            variant: variant,
                            caseIndex: caseIndex
                        ),
                        expected: .findings([
                            AIConnectorPhaseZeroExpectedFinding(
                                category: .spelling,
                                original: original,
                                replacement: replacement
                            )
                        ]),
                        difficulty: caseIndex == 0 ? "easy" : "medium"
                    )
                )
            }
        }

        for variant in 1 ... 15 {
            let original = "wajib untuk"
            result.append(
                AIConnectorPhaseZeroFixture(
                    id: String(format: "p0-grammar-%02d", variant),
                    category: .grammar,
                    text: "Pihak \(variant) wajib untuk menyerahkan laporan berkala kepada Perusahaan.",
                    expected: .findings([
                        AIConnectorPhaseZeroExpectedFinding(
                            category: .grammar,
                            original: original,
                            replacement: "wajib"
                        )
                    ]),
                    difficulty: variant <= 5 ? "easy" : "medium"
                )
            )
        }

        for variant in 1 ... 8 {
            let prefix = variant == 1
                ? ""
                : "Dalam dokumen \(variant), "
            result.append(
                AIConnectorPhaseZeroFixture(
                    id: String(format: "p0-terminology-%02d", variant),
                    category: .terminology,
                    text: "\(prefix)\(dataPribadiDefinition).",
                    expected: .findings([
                        AIConnectorPhaseZeroExpectedFinding(
                            category: .terminology,
                            original: dataPribadiDefinition,
                            replacement: "Data Pribadi"
                        )
                    ]),
                    difficulty: variant <= 3 ? "medium" : "hard"
                )
            )
        }

        let definitionFixtures: [(String, String, AIConnectorDefinitionClassification, AIConnectorDefinitionAlignment, String)] = [
            (
                "Data Pribadi adalah \(dataPribadiDefinition.lowercased()).",
                "explicit-match-1",
                .explicitDefinition,
                .matches,
                "easy"
            ),
            (
                "Data Pribadi merupakan \(dataPribadiDefinition.lowercased()).",
                "explicit-match-2",
                .explicitDefinition,
                .matches,
                "medium"
            ),
            (
                "Yang dimaksud dengan Data Pribadi adalah \(dataPribadiDefinition.lowercased()).",
                "explicit-match-3",
                .explicitDefinition,
                .matches,
                "medium"
            ),
            (
                "Data Pribadi adalah segala sesuatu yang berkaitan dengan kegiatan usaha dan pembayaran.",
                "explicit-mismatch-1",
                .explicitDefinition,
                .mismatch,
                "medium"
            ),
            (
                "Data Pribadi merupakan dokumen komersial yang ditandatangani para pihak.",
                "explicit-mismatch-2",
                .explicitDefinition,
                .mismatch,
                "hard"
            ),
            (
                "Data Pribadi wajib dilindungi oleh Pengendali Data Pribadi.",
                "mention-not-definition",
                .notDefinition,
                .notApplicable,
                "easy"
            ),
            (
                "Para Pihak wajib menjaga keamanan Data Pribadi sesuai kebijakan internal.",
                "mention-not-definition-2",
                .notDefinition,
                .notApplicable,
                "medium"
            )
        ]
        for (fixtureText, suffix, classification, alignment, difficulty) in definitionFixtures {
            result.append(
                AIConnectorPhaseZeroFixture(
                    id: "p0-definition-\(suffix)",
                    category: .definition,
                    text: fixtureText,
                    expected: .definition(
                        AIConnectorPhaseZeroExpectedDefinition(
                            classification: classification,
                            alignment: alignment
                        )
                    ),
                    difficulty: difficulty
                )
            )
        }

        let hardNegatives = [
            "Perjanjian ini berlaku sejak tanggal ditandatangani oleh Para Pihak.",
            "Pembayaran dilakukan melalui rekening yang disepakati Para Pihak.",
            "Pemberitahuan disampaikan secara tertulis kepada alamat resmi.",
            "Setiap perubahan Perjanjian dibuat dalam bentuk tertulis.",
            "Perusahaan menyimpan catatan transaksi sesuai kebijakan internal.",
            "Pihak Pertama menerima laporan pada hari kerja berikutnya.",
            "Para Pihak menyelesaikan perselisihan melalui musyawarah.",
            "Kerahasiaan informasi tetap berlaku setelah Perjanjian berakhir.",
            "Dokumen pendukung menjadi bagian yang tidak terpisahkan dari Perjanjian.",
            "Jangka waktu Perjanjian adalah dua belas bulan.",
            "Kewajiban pembayaran tidak menghapus kewajiban pelaporan.",
            "Perusahaan menunjuk wakil yang berwenang untuk komunikasi.",
            "Hak dan kewajiban Para Pihak mengikuti ketentuan Perjanjian.",
            "Pengakhiran Perjanjian tidak menghapus kewajiban yang telah timbul.",
            "Lampiran ini dibaca bersama dengan dokumen utama."
        ]
        for (index, text) in hardNegatives.enumerated() {
            result.append(
                AIConnectorPhaseZeroFixture(
                    id: String(format: "p0-hard-negative-%02d", index + 1),
                    category: .hardNegative,
                    text: text,
                    expected: .noChange,
                    difficulty: index < 5 ? "easy" : "hard"
                )
            )
        }

        return result
    }()

    static var samples: [AIConnectorSample] {
        fixtures.map { fixture in
            AIConnectorSample(
                id: fixture.id,
                title: fixture.id,
                text: fixture.text,
                expectedSignal: fixture.category.rawValue
            )
        }
    }

    private static func spellingText(
        variant: Int,
        caseIndex: Int
    ) -> String {
        switch caseIndex {
        case 0:
            return "Pihak \(variant) memasukan laporan dan data pendukung kepada Perusahaan."
        case 1:
            return "Perjanjian \(variant) telah ditanda tangani oleh Para Pihak pada tanggal 10 Agustus 2026."
        default:
            return "Dokumen \(variant) di simpan oleh Pihak Kedua dalam arsip elektronik."
        }
    }
}
#endif
