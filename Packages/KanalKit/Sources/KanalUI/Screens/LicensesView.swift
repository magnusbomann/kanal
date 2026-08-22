import KanalCore
import SwiftUI

/// What Kanal is built on, and what that means for the person using it.
///
/// VLC is LGPL, which permits it inside a proprietary app on three conditions:
/// publish any changes made to it, make the viewer aware it is embedded, and
/// make them aware of their rights and where the source lives. Kanal changes
/// nothing in VLC, so this screen covers the other two — and is the reason it
/// exists rather than being decoration.
public struct LicensesView: View {

    public init() {}

    public var body: some View {
        List {
            Section {
                Text(UIStrings.licensesIntro)
                    .font(KanalFont.body(13))
                    .foregroundStyle(KanalColor.secondaryText)
            }

            ForEach(Component.all) { component in
                Section(component.name) {
                    Text(component.purpose)
                        .font(KanalFont.body(13))
                        .foregroundStyle(KanalColor.secondaryText)
                    LabeledContent(String(UIStrings.licenseLabel), value: component.license)
                    if let url = component.sourceURL {
                        Link(destination: url) {
                            Label(String(UIStrings.viewSource), systemImage: "arrow.up.right.square")
                        }
                    }
                }
            }

            Section {
                Text(UIStrings.licensesRelink)
                    .font(KanalFont.body(12))
                    .foregroundStyle(KanalColor.tertiaryText)
            }
        }
        .navigationTitle(Text(UIStrings.licenses))
        .kanalPlainListBackground()
        .background(KanalColor.background)
    }

    struct Component: Identifiable {
        let id = UUID()
        let name: String
        let purpose: LocalizedStringResource
        let license: String
        let sourceURL: URL?

        static let all: [Component] = [
            Component(
                name: "VLCKit",
                purpose: UIStrings.creditVLCPurpose,
                license: "LGPL v2.1 or later",
                sourceURL: URL(string: "https://code.videolan.org/videolan/VLCKit")
            ),
            Component(
                name: "Wikidata",
                purpose: UIStrings.creditWikidataPurpose,
                license: "CC0 1.0",
                sourceURL: URL(string: "https://www.wikidata.org")
            ),
        ]
    }
}
