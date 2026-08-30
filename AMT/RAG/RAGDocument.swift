import Foundation

public struct RAGDocument: Codable, Identifiable, Hashable, Sendable {
    public let istilah: String
    public let pengertian: String
    public let undangUndang: String
    public let url: String

    public var id: String { istilah }

    public init(istilah: String, pengertian: String, undangUndang: String, url: String) {
        self.istilah = istilah
        self.pengertian = pengertian
        self.undangUndang = undangUndang
        self.url = url
    }

    enum CodingKeys: String, CodingKey {
        case istilah
        case pengertian
        case undangUndang = "undang_undang"
        case url
    }
}
