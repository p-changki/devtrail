import Foundation

/// DevTrail 헬퍼 — `python3` 를 대체한다 (ADR 0006 D2 = B).
///
/// ⚠️ 왜 이게 있나
///
///    비개발자 Mac 에는 python3 가 없다. `/usr/bin/python3` 는 Command Line
///    Tools 셰임이라, 실행하면 개발자 도구 설치 다이얼로그가 뜬다 — 거기서
///    설치가 끝난다. bash 와 jq 는 Apple 이 주므로 남은 차단 요인은 이것
///    하나였다.
///
/// ⚠️ 목표는 "더 나은 출력" 이 아니라 **같은 출력**이다.
///    tests/golden/gen/*.txt 를 바이트로 통과해야 한다. 통과하지 못하면
///    이관이 아니라 변경이다.
///
/// ⚠️ 셸은 이 바이너리가 없으면 python3 로 폴백한다. 그래서 이관이 끝나기
///    전에도 저장소는 그대로 동작하고, 기존 Git 설치형 사용자는 아무것도
///    잃지 않는다.
let args = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    사용법: devtrail-helper <명령> [인자…]

      gen-smartenv <tree> <config> <templates_dir> [<existing>]
      gen-anm      <tree> <config> <profile> [<existing>]
      gen-hotkeys  <hotkeys|templater|daily> <spec> <paths> [<existing>] [<ids>]
      gen-hub      (환경변수 DT_HUB_* 로 받는다)
      gen-snapshot '<cfg-json>'
      version

    ⚠️ 아직 이관 중입니다. 없는 명령은 셸이 python3 로 폴백합니다.
    """.utf8))
    FileHandle.standardError.write(Data("\n".utf8))
    exit(2)
}

guard let command = args.first else { usage() }
let rest = Array(args.dropFirst())

switch command {
case "gen-smartenv":
    exit(SmartEnv.run(rest))
case "gen-anm":
    exit(AutoNoteMover.run(rest))
case "gen-hotkeys":
    exit(Hotkeys.run(rest))
case "gen-hub":
    exit(FolderHub.run(rest))
case "gen-snapshot":
    exit(VaultSnapshot.run(rest))
case "version":
    // ⚠️ 버전을 여기 박지 않는다. VERSION 파일이 정본이다 (ADR 0006 §6).
    //    빌드가 주입하기 전까지는 모른다고 말한다 — 지어내지 않는다.
    print(ProcessInfo.processInfo.environment["DT_HELPER_VERSION"] ?? "unknown")
    exit(0)
default:
    FileHandle.standardError.write(Data("알 수 없는 명령: \(command)\n".utf8))
    usage()
}
