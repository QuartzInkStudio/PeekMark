import Foundation

public enum PeekMarkTypography {
    public static var appFontURLs: [URL] {
        ["InstrumentSerif", "IBMPlexMono"].compactMap {
            Bundle.module.url(forResource: $0, withExtension: "ttf")
        }
    }

    private static let displayFace: String = {
        guard let url = Bundle.module.url(forResource: "InstrumentSerif", withExtension: "ttf"),
              let data = try? Data(contentsOf: url) else { return "" }
        return "@font-face {font-family: 'Instrument Serif';src:url(data:font/ttf;base64,\(data.base64EncodedString())) format('truetype');font-display:swap;}"
    }()

    public static func pdfCustomization(
        combining preferred: RenderCustomization
    ) -> RenderCustomization {
        let printStyle = """
        \(displayFace)
        :root, .markdown-body.peekmark-pdf {
          --fgColor-default:#20283D;--fgColor-muted:#525D70;--fgColor-accent:#354BD1;
          --bgColor-default:#FFFEFB;--bgColor-muted:#F4F5FC;--borderColor-default:#DDD8CE;
          color-scheme:light
        }
        html,body,.markdown-body.peekmark-pdf {background:#FFFEFB;color:#20283D}
        .markdown-body.peekmark-pdf {padding:28px 37px;max-width:none;font-size:15px;font-variant-ligatures:none}
        .peekmark-pdf .peekmark-toc,.peekmark-pdf .peekmark-heading-anchor {display:none}
        .peekmark-pdf h1,.peekmark-pdf h2,.peekmark-pdf h3 {
          font-family:'Instrument Serif',Georgia,serif;font-weight:400;line-height:1.08;
          border:none
        }
        .peekmark-pdf h1 {font-size:50px;margin-top:0}
        .peekmark-pdf h2 {font-size:31px}
        .peekmark-pdf h3 {font-size:23px}
        .peekmark-pdf table {width:100%;display:table;border-collapse:collapse}
        .peekmark-pdf th,.peekmark-pdf td {border:none;border-bottom:1px solid #DDD8CE;text-align:left}
        .peekmark-pdf th {border-top:1px solid #20283D}
        .peekmark-pdf tr:nth-child(2n) {background:transparent}
        """
        return RenderCustomization(
            identifier: preferred.identifier,
            additionalCSS: printStyle + "\n" + preferred.additionalCSS,
            articleClassNames: ["peekmark-pdf"] + preferred.articleClassNames
        )
    }

    public static func readerCustomization(
        combining preferred: RenderCustomization
    ) -> RenderCustomization {
        let shared = """
        \(displayFace)
        :root,.markdown-body.peekmark-reader {--fgColor-default:#20283D;--fgColor-muted:#525D70;--fgColor-accent:#354BD1;--bgColor-default:#FCFAF5;--bgColor-muted:#EBEDFB;--borderColor-default:#D5CFBF}
        html,body,.markdown-body.peekmark-reader {background:var(--bgColor-default);color:var(--fgColor-default)}
        @media(prefers-color-scheme:dark) {:root,.markdown-body.peekmark-reader {--fgColor-default:#F3EFE7;--fgColor-muted:#B9C1D3;--fgColor-accent:#AFBAFF;--bgColor-default:#272E42;--bgColor-muted:#293767;--borderColor-default:#455067}}
        .markdown-body.peekmark-reader {max-width:1025px;padding:44px clamp(26px,11%,110px) 60px;line-height:1.6}
        .peekmark-reader .peekmark-toc {display:none}
        .peekmark-reader .peekmark-frontmatter {box-shadow:none;border-radius:6px;background:var(--bgColor-muted);margin-bottom:20px}
        .peekmark-reader h1,.peekmark-reader h2,.peekmark-reader h3 {font-family:'Instrument Serif',Georgia,serif;font-weight:400;line-height:1.05}
        .peekmark-reader h1 {font-size:clamp(42px,8vw,72px);border:none;padding:0;margin:0 0 12px}
        .peekmark-reader h1 + p {font-size:18px;color:var(--fgColor-muted);margin-bottom:22px;padding-bottom:21px;border-bottom:1px solid var(--borderColor-default)}
        .peekmark-reader h2 {font-size:36px;border:none;padding:0;margin:22px 0 10px}
        .peekmark-reader h3 {font-size:30px;margin:26px 0 10px}
        .peekmark-reader table {width:100%;display:table;border-collapse:collapse}
        .peekmark-reader th,.peekmark-reader td {border:none;border-bottom:1px solid var(--borderColor-default);text-align:left;padding:10px 4px}
        .peekmark-reader th {border-top:1px solid var(--fgColor-default);font-size:12px;font-family:var(--fontStack-monospace);letter-spacing:.06em;text-transform:uppercase}
        .peekmark-reader tr:nth-child(2n) {background:transparent}
        .peekmark-reader .mermaid {border:0;border-radius:6px;padding:10px}
        .peekmark-reader .mermaid svg {max-height:84px}
        .peekmark-reader .peekmark-heading-anchor {display:none}
        @media(max-width:690px) {
          .markdown-body.peekmark-reader {padding:32px 32px 50px}
          .peekmark-reader h1 {font-size:52px}
          .peekmark-reader h2 {font-size:30px}
        }
        """
        return RenderCustomization(
            identifier: preferred.identifier,
            additionalCSS: shared + "\n" + preferred.additionalCSS,
            articleClassNames: ["peekmark-reader"] + preferred.articleClassNames
        )
    }
}
