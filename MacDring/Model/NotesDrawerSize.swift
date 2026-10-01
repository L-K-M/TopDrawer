import Foundation

/// Logical-point size and normalized tab alignment, without absolute coordinates.
/// Alignment runs top-to-bottom on vertical edges, left-to-right on horizontal ones.
struct NotesDrawerSize: Codable, Equatable {
    let width: Double
    let height: Double
    let tabPosition: Double

    init?(width: Double, height: Double, tabPosition: Double = 0.5) {
        guard width.isFinite, height.isFinite, tabPosition.isFinite,
              width > 0, height > 0,
               (0...1).contains(tabPosition) else { return nil }

        self.width = width
        self.height = height
        self.tabPosition = tabPosition
    }

    private enum CodingKeys: String, CodingKey {
        case width, height, tabPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let width = try container.decode(Double.self, forKey: .width)
        let height = try container.decode(Double.self, forKey: .height)
        let tabPosition = try container.decodeIfPresent(Double.self, forKey: .tabPosition) ?? 0.5

        guard let valid = Self(width: width, height: height, tabPosition: tabPosition) else {
            throw DecodingError.dataCorruptedError(
                forKey: .width,
                in: container,
                debugDescription: "NotesDrawerSize requires finite positive width/height and tabPosition in 0...1"
            )
        }
        self = valid
    }
}
