import Foundation

enum LocalStorage {
    static func load<Value: Decodable>(_ type: Value.Type, named filename: String) throws -> Value? {
        let url = try fileURL(named: filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder.setlist.decode(Value.self, from: Data(contentsOf: url))
    }

    static func save<Value: Encodable>(_ value: Value, named filename: String) throws {
        let url = try fileURL(named: filename)
        let data = try JSONEncoder.setlist.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private static func fileURL(named filename: String) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Setlist", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent(filename)
    }
}
