import Foundation
import CryptoKit

/// 大对象落盘：按内容哈希命名，天然去重。
public final class BlobStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func store(_ data: Data) throws -> String {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let name = digest + ".bin"
        let url = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
        }
        return name
    }

    public func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    public func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }

    public func allNames() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
    }
}
