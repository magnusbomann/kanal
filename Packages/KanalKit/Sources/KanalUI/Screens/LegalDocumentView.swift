import SwiftUI

/// Offline copy of the public legal documents. Keeping this in the app means
/// App Review and users can inspect the terms even when the website is down.
public struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    public enum Document: String, Identifiable, Sendable {
        case terms
        case privacy

        public var id: String { rawValue }
        fileprivate var title: LocalizedStringResource {
            switch self {
            case .terms: UIStrings.proTerms
            case .privacy: UIStrings.proPrivacy
            }
        }
    }

    public let document: Document

    public init(document: Document) {
        self.document = document
    }

    public var body: some View {
        ScrollView {
            #if os(tvOS)
            // A television scrolls by moving focus, and one block of text has
            // nowhere for focus to go: only the first screenful of the terms
            // could be read. Each paragraph is a stop.
            LazyVStack(alignment: .leading, spacing: KanalMetrics.md) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(verbatim: paragraph)
                        .font(KanalFont.body(15))
                        .foregroundStyle(KanalColor.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focusable()
                }
            }
            .padding(KanalMetrics.lg)
            #else
            Text(verbatim: contents)
                .font(KanalFont.body(15))
                .foregroundStyle(KanalColor.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(KanalMetrics.lg)
            #endif
        }
        .background(KanalColor.background)
        .navigationTitle(Text(document.title))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(UIStrings.done)) { dismiss() }
                    .accessibilityLabel(Text(UIStrings.done))
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var paragraphs: [String] {
        contents.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var contents: String {
        guard let url = Bundle.module.url(forResource: document.rawValue, withExtension: "txt", subdirectory: "legal"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return ""
        }
        return text
    }
}
