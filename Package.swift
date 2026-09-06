// swift-tools-version:5.9
import PackageDescription

// ClipMate —— macOS 剪贴板历史工具
// 零第三方依赖：存储直接使用系统 SQLite3（FTS5 特性探测，降级 LIKE）。
let package = Package(
    name: "ClipMate",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClipMate",
            path: "Sources/ClipMate"
        ),
        // 本环境仅安装了 Command Line Tools（无 XCTest），
        // 单元测试以独立可执行 runner 的形式实现：swift run ClipMateTests
        .executableTarget(
            name: "ClipMateTests",
            dependencies: ["ClipMate"],
            path: "Tests/ClipMateTests"
        ),
    ]
)
