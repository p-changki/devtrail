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
        ),
        // ⚠️ python3 를 대체하는 헬퍼 (ADR 0006 D2 = B).
        //    비개발자 Mac 에 python3 가 없다 — /usr/bin/python3 는 Command
        //    Line Tools 셰임이라 실행하면 설치 다이얼로그가 뜬다.
        //    bash 와 jq 는 Apple 이 주므로 남은 차단 요인은 이것 하나였다.
        //
        //    앱과 **분리된 실행 파일**이다. 셸이 직접 부르고, 없으면
        //    python3 로 폴백한다 — 이관 중에도 저장소가 그대로 돈다.
        .executableTarget(
            name: "DevTrailHelper",
            path: "Sources/DevTrailHelper"
        )
    ]
)
