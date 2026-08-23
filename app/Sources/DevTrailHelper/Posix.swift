import Foundation

/// 파일 이름의 **바이트를 그대로** 쓰는 최소 계층.
///
/// ⚠️ 왜 Foundation 을 안 쓰는가
///
///    `String.write(toFile:)` 은 경로를 파일시스템 표현으로 바꾸면서 한글을
///    **NFD(자모 분해)** 로 만든다. python 은 NFC 그대로 쓴다:
///
///        python : 대  →  eb 8c 80              (U+B300)
///        Swift  : 대  →  e1 84 83 e1 85 a2     (ᄃ + ᅢ)
///
///    내용은 같은데 **파일 이름의 바이트가 다르다.** 골든이 파일 목록을
///    포함하므로 이 차이가 그대로 드러났다(2026-08-24). 사용자 볼트에서도
///    같은 이름의 파일이 둘로 보이거나, 링크가 깨지는 종류의 문제다.
///
///    APFS 는 정규화에 **둔감하되 보존**한다 — 그래서 존재 확인은 어느
///    형태로 물어도 찾지만, 만들 때의 바이트는 우리가 정한 대로 남는다.
enum Posix {

    /// 경로가 있는가. `access(2)`.
    static func exists(_ path: String) -> Bool {
        path.withCString { access($0, F_OK) == 0 }
    }

    /// 파일을 만든다. 이미 있으면 덮어쓴다 — 부르는 쪽이 먼저 확인한다.
    @discardableResult
    static func write(path: String, contents: String) -> Bool {
        let fd = path.withCString { open($0, O_WRONLY | O_CREAT | O_TRUNC, 0o644) }
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var bytes = Array(contents.utf8)
        var off = 0
        while off < bytes.count {
            let n = bytes[off...].withUnsafeBufferPointer {
                Foundation.write(fd, $0.baseAddress, $0.count)
            }
            if n <= 0 { return false }
            off += n
        }
        return true
    }
}
