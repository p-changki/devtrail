import SwiftUI

/// DevTrail 디자인 토큰.
///
/// 단일 출처는 `docs/design-tokens.md` 다. 여기서 색을 새로 고르지 않는다 —
/// 필요하면 문서를 먼저 고치고 다섯 표면을 함께 맞춘다.
///
/// 텍스트 색은 SwiftUI 시맨틱(`.primary` · `.secondary` · `.tertiary`)을 그대로 쓴다.
/// 시스템 다크모드와 접근성 설정을 자동으로 따르기 때문에 우리가 다시 정의하면 손해다.
/// 여기 정의하는 것은 **상태색 셋**뿐이다.
extension Color {

    /// accent · success — 완료 · 통과. 브랜드색과 같은 값이다.
    static let dtSuccess = Color(light: 0x2F6B4F, dark: 0x74C397)

    /// warning — 주의 · 확인 필요
    static let dtWarning = Color(light: 0x8D6316, dark: 0xD6A75C)

    /// danger — 실패 · 파괴적 동작
    static let dtDanger = Color(light: 0x8C3F36, dark: 0xDD8B80)

    /// 라이트·다크 값을 함께 받는다.
    ///
    /// 한쪽만 정의하면 다른 테마에서 대비가 무너진다. 실제로 라이트에서 읽히던 색이
    /// 다크 배경에서 안 보이는 일이 흔하다. 두 값을 강제로 받게 해서 그걸 막는다.
    private init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green:   CGFloat((hex >> 8) & 0xFF) / 255,
            blue:    CGFloat(hex & 0xFF) / 255,
            alpha:   1
        )
    }
}
