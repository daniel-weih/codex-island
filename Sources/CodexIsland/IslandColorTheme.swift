import SwiftUI

enum IslandColorTheme: String, CaseIterable, Identifiable {
    case ocean
    case meituan
    case bytedance
    case alibaba
    case tencent
    case tsinghua

    static let storageKey = "codexIsland.colorTheme"

    var id: String { rawValue }

    static func stored(_ rawValue: String) -> IslandColorTheme {
        IslandColorTheme(rawValue: rawValue) ?? .ocean
    }

    var accent: Color {
        switch self {
        case .ocean:
            return Color(red: 0.02, green: 0.78, blue: 0.95)
        case .meituan:
            return Color(red: 1.00, green: 209.0 / 255.0, blue: 0.00) // #FFD100
        case .bytedance:
            return Color(
                red: 120.0 / 255.0,
                green: 230.0 / 255.0,
                blue: 220.0 / 255.0
            ) // #78E6DC
        case .alibaba:
            return Color(red: 1.00, green: 106.0 / 255.0, blue: 0.00) // #FF6A00
        case .tencent:
            return Color(red: 30.0 / 255.0, green: 111.0 / 255.0, blue: 1.00) // #1E6FFF
        case .tsinghua:
            // Screen-safe tint of Tsinghua's official RGB(102, 8, 116)
            // mixed with the university's second school color, white.
            return Color(red: 0.63, green: 0.40, blue: 0.67)
        }
    }

    var secondaryAccent: Color {
        switch self {
        case .ocean:
            return Color(red: 0.16, green: 0.42, blue: 1.00)
        case .meituan:
            return Color(red: 1.00, green: 0.60, blue: 0.00)
        case .bytedance:
            return Color(
                red: 60.0 / 255.0,
                green: 140.0 / 255.0,
                blue: 1.00
            ) // #3C8CFF
        case .alibaba:
            return Color(red: 1.00, green: 0.69, blue: 0.00)
        case .tencent:
            return Color(red: 0.00, green: 0.64, blue: 1.00)
        case .tsinghua:
            return Color(
                red: 102.0 / 255.0,
                green: 8.0 / 255.0,
                blue: 116.0 / 255.0
            )
        }
    }

    var watermarkResourceName: String? {
        switch self {
        case .ocean: return nil
        case .meituan: return "MeituanKangarooWatermark"
        case .bytedance: return "ByteDanceLogoReverse"
        case .alibaba: return "AlibabaLogo"
        case .tencent: return "TencentLogoReverse"
        case .tsinghua: return "TsinghuaEmblemReverse"
        }
    }

    var watermarkSize: CGSize {
        switch self {
        case .ocean: return .zero
        case .meituan: return CGSize(width: 226, height: 226)
        case .bytedance: return CGSize(width: 220, height: 220)
        case .alibaba: return CGSize(width: 220, height: 220)
        case .tencent: return CGSize(width: 216, height: 216)
        case .tsinghua: return CGSize(width: 176, height: 176)
        }
    }

    var watermarkOpacity: Double {
        switch self {
        case .ocean: return 0
        case .meituan: return 0.085
        case .bytedance: return 0.10
        case .alibaba, .tencent: return 0.085
        case .tsinghua: return 0.075
        }
    }

    var usesOriginalWatermarkColors: Bool {
        self == .meituan || self == .tsinghua
    }

    func label(language: IslandInterfaceLanguage) -> String {
        switch self {
        case .ocean: return language.text("深海", "Ocean")
        case .meituan: return language.text("美团", "Meituan")
        case .bytedance: return language.text("字节", "ByteDance")
        case .alibaba: return language.text("阿里", "Alibaba")
        case .tencent: return language.text("腾讯", "Tencent")
        case .tsinghua: return language.text("清华", "Tsinghua")
        }
    }
}
