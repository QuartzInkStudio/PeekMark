import AppKit
import Combine
import CoreText
import QuickMarkCore

enum PeekMarkAppearance {
    enum Role {
        case shell, rail, paper, ink, muted, line, blue, soft, accentText, status, pdfCanvas

        var pair: (Int, Int) {
            switch self {
            case .shell: (0xF3EFE7, 0x202536)
            case .rail: (0xEAE5DA, 0x1B2030)
            case .paper: (0xFCFAF5, 0x272E42)
            case .ink: (0x20283D, 0xF3EFE7)
            case .muted: (0x525D70, 0xB9C1D3)
            case .line: (0xD5CFBF, 0x455067)
            case .blue: (0x354BD1, 0xAFBAFF)
            case .soft: (0xEBEDFB, 0x293767)
            case .accentText: (0xFFFFFF, 0x182541)
            case .status: (0x236045, 0xA5DBBC)
            case .pdfCanvas: (0xE8E5DF, 0x22293B)
            }
        }
    }

    static func color(_ role: Role) -> NSColor {
        let (light, dark) = role.pair
        return NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(value >> 16 & 255) / 255,
                           green: CGFloat(value >> 8 & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }

    private static let registerFonts: Void = {
        for url in PeekMarkTypography.appFontURLs {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func displayFont(size: CGFloat) -> NSFont {
        _ = registerFonts
        if let font = NSFont(name: "InstrumentSerif-Regular", size: size) { return font }
        if let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif),
           let font = NSFont(descriptor: descriptor, size: size) { return font }
        return NSFont.systemFont(ofSize: size)
    }

    static func monoFont(size: CGFloat) -> NSFont {
        _ = registerFonts
        return NSFont(name: "IBMPlexMono-Regular", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

@MainActor
final class PeekMarkWelcomeNavigation: ObservableObject {
    static let shared = PeekMarkWelcomeNavigation()
    @Published var helpRequested = false

    static func showHelp() {
        shared.helpRequested = true
    }
}
