import Foundation

/// Describes where rendered Markdown will be consumed.
///
/// This is intentionally edition-neutral so optional modules can extend the
/// renderer without the Community target depending on a private package.
public enum RenderPurpose: String, Sendable, Codable {
    case appPreview
    case quickLook
    case htmlExport
    case pdfExport
    case docxExport
}

public struct RenderContext: Sendable, Equatable {
    public let sourceURL: URL?
    public let title: String
    public let purpose: RenderPurpose

    public init(sourceURL: URL?, title: String, purpose: RenderPurpose) {
        self.sourceURL = sourceURL
        self.title = title
        self.purpose = purpose
    }
}

/// Trusted, local presentation changes applied while the HTML shell is built.
public struct RenderCustomization: Sendable, Equatable {
    public let identifier: String?
    public let additionalCSS: String
    public let articleClassNames: [String]

    public init(
        identifier: String? = nil,
        additionalCSS: String = "",
        articleClassNames: [String] = []
    ) {
        self.identifier = identifier
        self.additionalCSS = additionalCSS
        self.articleClassNames = articleClassNames
    }

    public static let none = RenderCustomization()
}

public protocol RenderCustomizationProviding: Sendable {
    var identifier: String { get }
    var displayName: String { get }
    func customization(for context: RenderContext) async throws -> RenderCustomization
}

public struct ExportFormat: Sendable, Equatable {
    public let identifier: String
    public let displayName: String
    public let filenameExtension: String
    public let mimeType: String

    public init(
        identifier: String,
        displayName: String,
        filenameExtension: String,
        mimeType: String
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.filenameExtension = filenameExtension
        self.mimeType = mimeType
    }
}

public struct ExportRequest: Sendable {
    public let html: String
    public let context: RenderContext
    public let destinationURL: URL

    public init(html: String, context: RenderContext, destinationURL: URL) {
        self.html = html
        self.context = context
        self.destinationURL = destinationURL
    }
}

public protocol DocumentExporting: Sendable {
    var format: ExportFormat { get }
    func export(_ request: ExportRequest) async throws
}

/// Paper and margins shared by the preview and the PDF it saves.
public struct PDFExportPreset: Codable, Hashable, Sendable {
    public enum Paper: String, Codable, CaseIterable, Sendable {
        case a4, usLetter
    }

    public enum Margins: String, Codable, CaseIterable, Sendable {
        case standard, compact
    }

    public var paper: Paper
    public var margins: Margins

    public init(paper: Paper = .a4, margins: Margins = .standard) {
        self.paper = paper
        self.margins = margins
    }
}

/// Renders generated, local Markdown HTML for on-screen PDF preview.
public protocol PDFPreviewRendering: Sendable {
    func renderPDF(html: String, sourceURL: URL?, preset: PDFExportPreset) async throws -> Data
}

public extension PDFPreviewRendering {
    func renderPDF(html: String, sourceURL: URL?) async throws -> Data {
        try await renderPDF(html: html, sourceURL: sourceURL, preset: PDFExportPreset())
    }
}
