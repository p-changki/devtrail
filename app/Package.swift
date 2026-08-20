// swift-tools-version: 5.9
import PackageDescription

// DevTrail 메뉴바 앱.
//
// 이 앱에는 비즈니스 로직이 없다. devtrail CLI를 호출하고 그 결과를 보여줄 뿐이다.
// 앱이 없어도 CLI는 그대로 동작하고, CLI가 바뀌면 앱은 자동으로 따라간다.
let package = Package(
    name: "DevTrail",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DevTrailApp",
            path: "Sources/DevTrailApp"
        )
    ]
)
