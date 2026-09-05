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
            Text(verbatim: contents)
                .font(KanalFont.body(15))
                .foregroundStyle(KanalColor.primaryText)
                #if !os(tvOS)
                .textSelection(.enabled)
                #endif
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(KanalMetrics.lg)
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

    private var contents: String {
        guard let url = Bundle.module.url(forResource: document.rawValue, withExtension: "txt", subdirectory: "legal"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return ""
        }
        return text
    }
}
