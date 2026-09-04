//
//  LegalGlossaryModel.swift
//  AMT
//
//  Created by Antigravity on 2026/08/27.
//

import Foundation

// MARK: - Legal Reference Model

/// Detailed statutory or institutional reference for a legal definition.
nonisolated struct LegalReference: Hashable, Sendable {
    let lawName: String
    let lawTitle: String?
    let institution: String?
    let dateEnacted: String?
    let dateEffective: String?
    let sourceURL: URL?
    let officialDocumentURL: URL?
    let referenceID: String?
    let applicabilityStatus: LegalCorpusApplicabilityStatus
    let articleLocator: String?
    let pageStart: Int?
    let pageEnd: Int?
    let sourcePassageID: String?

    init(
        lawName: String,
        lawTitle: String? = nil,
        institution: String? = nil,
        dateEnacted: String? = nil,
        dateEffective: String? = nil,
        sourceURL: URL? = nil,
        officialDocumentURL: URL? = nil,
        referenceID: String? = nil,
        applicabilityStatus: LegalCorpusApplicabilityStatus = .unknown,
        articleLocator: String? = nil,
        pageStart: Int? = nil,
        pageEnd: Int? = nil,
        sourcePassageID: String? = nil
    ) {
        self.lawName = lawName
        self.lawTitle = lawTitle
        self.institution = institution
        self.dateEnacted = dateEnacted
        self.dateEffective = dateEffective
        self.sourceURL = sourceURL
        self.officialDocumentURL = officialDocumentURL
        self.referenceID = referenceID
        self.applicabilityStatus = applicabilityStatus
        self.articleLocator = articleLocator
        self.pageStart = pageStart
        self.pageEnd = pageEnd
        self.sourcePassageID = sourcePassageID
    }
}

// MARK: - Definition Item Model

/// Represents a single numbered definition under a legal term.
nonisolated struct DefinitionItem: Identifiable, Hashable, Sendable {
    var id: Int
    let text: String
    let reference: LegalReference?
    let sources: [String]
    let sourceURLs: [URL]

    init(
        id: Int,
        text: String,
        reference: LegalReference? = nil,
        sources: [String] = [],
        sourceURLs: [URL] = []
    ) {
        self.id = id
        self.text = text
        self.reference = reference
        self.sources = sources
        self.sourceURLs = sourceURLs
    }
}

// MARK: - Legal Glossary Entry Model

/// Represents a dictionary or legal glossary definition entry with multiple definitions and "Lihat Juga" relations.
nonisolated struct LegalGlossaryEntry: Identifiable, Hashable, Sendable {
    var id: String { term.lowercased() }
    let term: String
    let definitions: [DefinitionItem]
    let seeAlso: [String]
    let authority: LegalDictionaryEntryAuthority
    let corpusVersion: String
    let applicabilityStatus: LegalCorpusApplicabilityStatus
    let isActionable: Bool
    let regulationRelations: [LegalRegulationRelation]

    init(
        term: String,
        definitions: [DefinitionItem],
        seeAlso: [String] = [],
        authority: LegalDictionaryEntryAuthority = .legacy,
        corpusVersion: String = LegalDictionaryCorpusVersion.unspecifiedLegacy,
        applicabilityStatus: LegalCorpusApplicabilityStatus = .unknown,
        isActionable: Bool = false,
        regulationRelations: [LegalRegulationRelation] = []
    ) {
        self.term = term
        self.definitions = definitions
        self.seeAlso = seeAlso
        self.authority = authority
        self.corpusVersion = corpusVersion
        self.applicabilityStatus = applicabilityStatus
        self.isActionable = isActionable
        self.regulationRelations = regulationRelations
    }

    /// Single-definition convenience initializer
    init(
        term: String,
        singleDefinition: String,
        reference: LegalReference? = nil,
        seeAlso: [String] = [],
        authority: LegalDictionaryEntryAuthority = .legacy,
        corpusVersion: String = LegalDictionaryCorpusVersion.unspecifiedLegacy,
        applicabilityStatus: LegalCorpusApplicabilityStatus = .unknown,
        isActionable: Bool = false,
        regulationRelations: [LegalRegulationRelation] = []
    ) {
        self.term = term
        self.definitions = [
            DefinitionItem(id: 1, text: singleDefinition, reference: reference)
        ]
        self.seeAlso = seeAlso
        self.authority = authority
        self.corpusVersion = corpusVersion
        self.applicabilityStatus = applicabilityStatus
        self.isActionable = isActionable
        self.regulationRelations = regulationRelations
    }
}

// MARK: - Popular Term Model

/// Represents a popular term displayed on the Lawtionary home screen.
nonisolated struct PopularTerm: Identifiable, Hashable, Sendable {
    var id: String { name.lowercased() }
    let name: String
    let tag: String?
    let score: Double?

    init(name: String, tag: String? = nil, score: Double? = nil) {
        self.name = name
        self.tag = tag
        self.score = score
    }

    // MARK: - Popular Term Random Selection

    static let candidatePopularTerms: [PopularTerm] = [
        PopularTerm(name: "Korporasi"),
        PopularTerm(name: "Perusahaan"),
        PopularTerm(name: "Ex Officio"),
        PopularTerm(name: "Pelaku Usaha"),
        PopularTerm(name: "Data Pribadi"),
        PopularTerm(name: "Hukum Adat"),
        PopularTerm(name: "Jaksa"),
        PopularTerm(name: "Beban Pembuktian"),
        PopularTerm(name: "Ganti Rugi"),
        PopularTerm(name: "Wanprestasi"),
        PopularTerm(name: "Tindak Pidana"),
        PopularTerm(name: "Hak Cipta"),
        PopularTerm(name: "Arbitrase"),
        PopularTerm(name: "Badan Hukum"),
        PopularTerm(name: "Subjek Hukum")
    ]

    /// Selects `count` random popular terms from candidates or store entries.
    static func randomPopularTerms(count: Int = 3, from entries: [LegalDictionaryEntry] = []) -> [PopularTerm] {
        var pool: [PopularTerm] = candidatePopularTerms
        if !entries.isEmpty {
            let entryTerms = entries.compactMap { entry -> PopularTerm? in
                let name = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name.count <= 25, !name.contains(";") else { return nil }
                return PopularTerm(name: name)
            }
            if !entryTerms.isEmpty {
                var uniqueDict = [String: PopularTerm]()
                for term in pool + entryTerms {
                    uniqueDict[term.name.lowercased()] = term
                }
                pool = Array(uniqueDict.values)
            }
        }
        return Array(pool.shuffled().prefix(max(0, count)))
    }

    static var defaultPopularTerms: [PopularTerm] {
        randomPopularTerms(count: 3)
    }

    // MARK: - Curated Legal Glossary Samples
    // TODO: [AI Team] Replace or enrich these mock entries with model inferences or a full vector/lexical database.
    static let sampleGlossaryEntries: [String: LegalGlossaryEntry] = [
        "jaksa": LegalGlossaryEntry(
            term: "Jaksa",
            definitions: [
                DefinitionItem(
                    id: 1,
                    text: "Pegawai negeri sipil dengan jabatan fungsional yang memiliki kekhususan dan melaksanakan tugas, fungsi, dan kewenangannya berdasarkan Undang-Undang",
                    reference: LegalReference(
                        lawName: "Undang-Undang Nomor 11 Tahun 2021",
                        institution: "Kejaksaan Agung",
                        dateEnacted: "31 Desember 2021",
                        dateEffective: "31 Desember 2021"
                    )
                ),
                DefinitionItem(
                    id: 2,
                    text: "Pegawai negeri sipil dengan jabatan fungsional yang memiliki kekhususan dan melaksanakan tugas, fungsi, dan kewenangannya berdasarkan Undang-Undang",
                    reference: LegalReference(
                        lawName: "Undang-Undang Nomor 11 Tahun 2021",
                        institution: "Kejaksaan Agung",
                        dateEnacted: "31 Desember 2021",
                        dateEffective: "31 Desember 2021"
                    )
                )
            ],
            seeAlso: [
                "Jaksa Agung",
                "Jabatan Fungsional",
                "Jabatan Struktural",
                "Jabatan Pimpinan Tinggi"
            ]
        ),
        "koporasi": LegalGlossaryEntry(
            term: "Korporasi",
            definitions: [
                DefinitionItem(
                    id: 1,
                    text: "Kumpulan orang dan/atau kekayaan yang terorganisasi, baik merupakan badan hukum maupun bukan badan hukum yang dapat dimintakan pertanggungjawaban hukum.",
                    reference: LegalReference(
                        lawName: "Undang-Undang Nomor 31 Tahun 1999 jo. UU No. 20 Tahun 2001",
                        institution: "Mahkamah Agung",
                        dateEnacted: "16 Agustus 1999",
                        dateEffective: "16 Agustus 1999"
                    )
                )
            ],
            seeAlso: [
                "Badan Usaha",
                "Entitas Bisnis",
                "Direksi",
                "Tindak Pidana Korporasi"
            ]
        ),
        "korporasi": LegalGlossaryEntry(
            term: "Korporasi",
            definitions: [
                DefinitionItem(
                    id: 1,
                    text: "Kumpulan orang dan/atau kekayaan yang terorganisasi, baik merupakan badan hukum maupun bukan badan hukum yang dapat dimintakan pertanggungjawaban hukum.",
                    reference: LegalReference(
                        lawName: "Undang-Undang Nomor 31 Tahun 1999 jo. UU No. 20 Tahun 2001",
                        institution: "Mahkamah Agung",
                        dateEnacted: "16 Agustus 1999",
                        dateEffective: "16 Agustus 1999"
                    )
                )
            ],
            seeAlso: [
                "Badan Usaha",
                "Entitas Bisnis",
                "Direksi"
            ]
        ),
        "perusahaan": LegalGlossaryEntry(
            term: "Perusahaan",
            definitions: [
                DefinitionItem(
                    id: 1,
                    text: "Setiap bentuk usaha yang menjalankan setiap jenis usaha yang bersifat tetap dan terus-menerus dan yang didirikan, bekerja serta berkedudukan dalam wilayah Negara Republik Indonesia, untuk tujuan memperoleh keuntungan dan/atau laba.",
                    reference: LegalReference(
                        lawName: "Undang-Undang Nomor 3 Tahun 1982",
                        institution: "Kementerian Hukum dan HAM",
                        dateEnacted: "1 Februari 1982",
                        dateEffective: "1 Februari 1982"
                    )
                )
            ],
            seeAlso: [
                "Perseroan Terbatas",
                "CV",
                "Firma",
                "Pelaku Usaha"
            ]
        ),
        "ex officio": LegalGlossaryEntry(
            term: "Ex Officio",
            definitions: [
                DefinitionItem(
                    id: 1,
                    text: "Tindakan, hak, atau kewenangan yang melekat dan dilakukan oleh seorang pejabat atau hakim berdasarkan kedudukan atau jabatan yang diembannya, tanpa memerlukan permohonan atau tuntutan terlebih dahulu dari para pihak.",
                    reference: LegalReference(
                        lawName: "Doktrin Asas Peradilan & Hukum Acara",
                        institution: "Mahkamah Agung RI",
                        dateEnacted: "1 Januari 2000",
                        dateEffective: "1 Januari 2000"
                    )
                )
            ],
            seeAlso: [
                "Ultra Petita",
                "Kewenangan Jabatan",
                "Asas Peradilan"
            ]
        ),
        "pelaku usaha": LegalGlossaryEntry(
            term: "Pelaku Usaha",
            definitions: [
                DefinitionItem(
                    id: 1,
                    text: "Setiap orang perseorangan atau badan usaha, baik yang berbentuk badan hukum maupun bukan badan hukum yang didirikan dan berkedudukan atau melakukan kegiatan dalam wilayah hukum negara Republik Indonesia, baik sendiri maupun bersama-sama menyelenggarakan kegiatan usaha dalam berbagai bidang ekonomi.",
                    reference: LegalReference(
                        lawName: "Undang-Undang Nomor 8 Tahun 1999",
                        institution: "Kementerian Perdagangan",
                        dateEnacted: "20 April 1999",
                        dateEffective: "20 April 2000"
                    )
                )
            ],
            seeAlso: [
                "Konsumen",
                "Klausula Baku",
                "Tanggung Jawab Produk"
            ]
        ),
        "data pribadi": LegalGlossaryEntry(
            term: "Data Pribadi",
            definitions: [
                DefinitionItem(
                    id: 1,
                    text: "Data tentang orang perseorangan yang teridentifikasi atau dapat diidentifikasi secara tersendiri atau dikombinasi dengan informasi lainnya baik secara langsung maupun tidak langsung melalui sistem elektronik atau nonelektronik.",
                    reference: LegalReference(
                        lawName: "Undang-Undang Nomor 27 Tahun 2022",
                        institution: "Kementerian Komunikasi dan Informatika",
                        dateEnacted: "17 Oktober 2022",
                        dateEffective: "17 Oktober 2022"
                    )
                )
            ],
            seeAlso: [
                "Subjek Data",
                "Pengendali Data",
                "Prosesor Data",
                "Kerahasiaan Informasi"
            ]
        )
    ]
}
