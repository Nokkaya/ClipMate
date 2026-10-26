import Foundation
import AppKit

/// 更新状态枚举
public enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate(version: String)
    case available(version: String, notes: String, downloadURL: URL)
    case failed(message: String)
}

/// 自动版本检查与更新管理器（兼容 Sparkle 2 Appcast 与 GitHub Releases 规范，100% 原生零第三方依赖）
public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()

    @Published public private(set) var state: UpdateState = .idle
    @Published public private(set) var isChecking: Bool = false

    /// 默认发布与下载页面
    public static let defaultReleasesURL = URL(string: "https://github.com/Nokkaya/ClipMate/releases")!

    /// 当前本地应用版本号
    public var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1"
    }

    /// 当前本地构建号
    public var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"
    }

    /// 远端 Appcast Feed URL（优先读取 Info.plist 的 SUFeedURL）
    public var feedURL: URL {
        if let feedString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           let url = URL(string: feedString) {
            return url
        }
        return URL(string: "https://raw.githubusercontent.com/Nokkaya/ClipMate/main/appcast.xml")!
    }

    private init() {}

    /// 检查软件更新
    /// - Parameter manual: 是否为用户主动点击（手动检查在最新或失败时均展示明确反馈；后台自动检查只在发现新版本时提示）
    public func checkForUpdates(settings: AppSettings? = nil, manual: Bool = true) {
        Task { @MainActor in
            guard !self.isChecking else { return }
            self.isChecking = true
            self.state = .checking
        }

        let localVersion = currentVersion
        let requestURL = feedURL

        Task {
            do {
                var request = URLRequest(url: requestURL)
                request.timeoutInterval = 8
                request.cachePolicy = .reloadIgnoringLocalCacheData

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                let parsed = self.parseAppcast(data: data)
                await MainActor.run {
                    if let (remoteVersion, notes, downloadURL) = parsed {
                        if Self.compareVersion(remoteVersion, greaterThan: localVersion) {
                            self.state = .available(version: remoteVersion, notes: notes, downloadURL: downloadURL)
                        } else {
                            self.state = .upToDate(version: localVersion)
                        }
                    } else {
                        self.state = .upToDate(version: localVersion)
                    }
                    settings?.lastUpdateCheckDate = Date()
                    self.isChecking = false
                }
            } catch {
                await MainActor.run {
                    if manual {
                        self.state = .failed(message: error.localizedDescription)
                    } else {
                        self.state = .idle
                    }
                    self.isChecking = false
                }
            }
        }
    }

    /// 打开新版本下载或主页
    @MainActor
    public func openDownloadPage() {
        if case .available(_, _, let url) = state {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(Self.defaultReleasesURL)
        }
    }

    /// 应用启动时静默检查
    public func checkOnLaunch(settings: AppSettings) {
        guard settings.autoCheckUpdates else { return }
        // 距离上次检查超过 24 小时才进行静默轮询
        if let last = settings.lastUpdateCheckDate, Date().timeIntervalSince(last) < 86400 {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.checkForUpdates(settings: settings, manual: false)
        }
    }

    // MARK: - 语义化版本对比算法 (Semantic Versioning)

    /// 比较 v1 是否严格大于 v2（如 "0.2.1" > "0.2.0", "1.0.0" > "0.9.9", "0.2.0.1" > "0.2.0"）
    public static func compareVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let clean1 = v1.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let clean2 = v2.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        let parts1 = clean1.split(separator: ".").compactMap { Int($0) }
        let parts2 = clean2.split(separator: ".").compactMap { Int($0) }

        let count = max(parts1.count, parts2.count)
        for i in 0..<count {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        return false
    }

    // MARK: - Appcast XML 解析

    /// 解析 Appcast，返回版本号最高的一条（公开以便单测覆盖多版本 feed）。
    public func parseAppcast(data: Data) -> (version: String, notes: String, downloadURL: URL)? {
        guard let xml = String(data: data, encoding: .utf8) else { return nil }

        // 逐条解析 <item> 并取版本号最高的一条（多版本 feed 不会因只读首个条目而漏读）。
        var best: (version: String, notes: String, downloadURL: URL)?
        var fallback: (version: String, notes: String, downloadURL: URL)?

        for raw in xml.components(separatedBy: "<item>").dropFirst() {
            let item = raw.components(separatedBy: "</item>").first ?? raw

            // 优先使用营销版本号；缺失时退回构建号，且仅在没有任何条目带营销版本号时才采用。
            // Sparkle 的短版本号既可能是元素也可能是属性（本项目生成的 appcast 用属性），两种都支持。
            let shortVersion = Self.firstMatch(
                in: item,
                patterns: [
                    #"(?<=<sparkle:shortVersionString>)[^<]+"#,
                    #"(?<=sparkle:shortVersionString=")[^"]+"#,
                ]
            )
            let buildVersion = Self.firstMatch(
                in: item,
                patterns: [
                    #"(?<=sparkle:version=")[^"]+"#,
                    #"(?<=<sparkle:version>)[^<]+"#,
                ]
            )
            guard let version = shortVersion ?? buildVersion else { continue }

            var downloadURL = Self.defaultReleasesURL
            if let urlString = Self.firstMatch(in: item, patterns: [#"(?<=<enclosure url=")[^"]+"#]),
               let parsedURL = URL(string: urlString) {
                downloadURL = parsedURL
            }

            let notes = Self.firstMatch(
                in: item,
                patterns: [#"(?<=<description><!\[CDATA\[)[\s\S]*?(?=\]\]></description>)"#]
            ) ?? ""

            let candidate = (version: version, notes: notes, downloadURL: downloadURL)
            guard shortVersion != nil else {
                if fallback == nil { fallback = candidate }
                continue
            }
            if let currentBest = best {
                if Self.compareVersion(version, greaterThan: currentBest.version) {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }

        return best ?? fallback
    }

    /// 返回首个正则匹配结果（按给定顺序尝试）。
    private static func firstMatch(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                return String(text[range])
            }
        }
        return nil
    }
}
