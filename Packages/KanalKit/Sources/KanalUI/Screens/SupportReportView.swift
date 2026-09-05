import KanalCore
import SwiftUI

struct SupportReportView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let report = model.makeSupportReport()
        ScrollView {
            VStack(alignment: .leading, spacing: KanalMetrics.lg) {
                Text(UIStrings.supportIntro)
                    .font(KanalFont.body(15))
                    .foregroundStyle(KanalColor.secondaryText)

                Label {
                    Text(UIStrings.supportPrivacy)
                        .font(KanalFont.body(13))
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(KanalColor.success)
                }

                #if !os(tvOS)
                ShareLink(item: report.text) {
                    Label(String(UIStrings.supportShare), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(KanalPrimaryButtonStyle(fullWidth: true))
                #endif

                VStack(alignment: .leading, spacing: KanalMetrics.sm) {
                    Text(UIStrings.supportReportLabel)
                        .kanalLabel(12)
                        .foregroundStyle(KanalColor.tertiaryText)
                    Text(verbatim: report.text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(KanalColor.secondaryText)
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(KanalMetrics.md)
                .background(KanalColor.surface, in: .rect(cornerRadius: 16, style: .continuous))
            }
            .padding(KanalMetrics.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(KanalColor.background)
        .navigationTitle(Text(UIStrings.supportTitle))
    }
}
