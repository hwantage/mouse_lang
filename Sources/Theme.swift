import Cocoa

struct Theme {
    let name: String
    let koreanBg: NSColor
    let englishBg: NSColor
    let textColor: NSColor
    let borderColor: NSColor
    let borderWidth: CGFloat

    static let dark = Theme(
        name: "다크",
        koreanBg: NSColor(red: 0.15, green: 0.25, blue: 0.55, alpha: 0.9),
        englishBg: NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 0.9),
        textColor: .white,
        borderColor: NSColor.white.withAlphaComponent(0.25),
        borderWidth: 0.5
    )

    static let light = Theme(
        name: "라이트",
        koreanBg: NSColor(red: 0.95, green: 0.95, blue: 1.0, alpha: 0.95),
        englishBg: NSColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 0.95),
        textColor: NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0),
        borderColor: NSColor.gray.withAlphaComponent(0.3),
        borderWidth: 0.5
    )

    static let liquid = Theme(
        name: "리퀴드",
        koreanBg: NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.55),
        englishBg: NSColor(red: 0.3, green: 0.3, blue: 0.5, alpha: 0.45),
        textColor: .white,
        borderColor: NSColor.white.withAlphaComponent(0.4),
        borderWidth: 1.0
    )

    static let pink = Theme(
        name: "핑크",
        koreanBg: NSColor(red: 1.0, green: 0.75, blue: 0.82, alpha: 0.9),
        englishBg: NSColor(red: 1.0, green: 0.85, blue: 0.88, alpha: 0.9),
        textColor: NSColor(red: 0.4, green: 0.1, blue: 0.2, alpha: 1.0),
        borderColor: NSColor(red: 1.0, green: 0.6, blue: 0.7, alpha: 0.4),
        borderWidth: 0.5
    )

    static let mint = Theme(
        name: "민트",
        koreanBg: NSColor(red: 0.6, green: 0.92, blue: 0.85, alpha: 0.9),
        englishBg: NSColor(red: 0.75, green: 0.95, blue: 0.9, alpha: 0.9),
        textColor: NSColor(red: 0.05, green: 0.3, blue: 0.25, alpha: 1.0),
        borderColor: NSColor(red: 0.4, green: 0.8, blue: 0.7, alpha: 0.4),
        borderWidth: 0.5
    )

    static let allThemes: [Theme] = [.dark, .light, .liquid, .pink, .mint]
}
