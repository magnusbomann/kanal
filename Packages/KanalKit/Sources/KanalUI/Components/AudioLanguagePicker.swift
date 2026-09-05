import KanalCore
import SwiftUI

/// Choosing which language a film should start in.
///
/// One control in two places, because it is one preference. A grown-up finds
/// it in Settings and it starts at "original language"; a child's is set when
/// the profile is made and a parent adjusts it in the same editor where they
/// set the age limit.
struct AudioLanguagePicker: View {
    @Binding var selection: String?
    /// Explains what leaving it alone means, which differs by who is being
    /// set up. Passed in rather than derived so neither caller has to know
    /// about the other.
    let footer: LocalizedStringResource

    private var codes: [String] { AudioLanguagePreference.offered() }

    var body: some View {
        Section {
            #if !os(tvOS)
            Menu {
                Button {
                    selection = nil
                } label: {
                    if selection == nil {
                        Label(String(UIStrings.audioLanguageOriginal), systemImage: "checkmark")
                    } else {
                        Text(UIStrings.audioLanguageOriginal)
                    }
                }
                ForEach(codes, id: \.self) { code in
                    Button {
                        selection = code
                    } label: {
                        if selection == code {
                            Label(AudioLanguagePreference.displayName(code), systemImage: "checkmark")
                        } else {
                            Text(verbatim: AudioLanguagePreference.displayName(code))
                        }
                    }
                }
            } label: {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: KanalMetrics.md) {
                        Text(UIStrings.audioLanguage)
                            .foregroundStyle(KanalColor.primaryText)
                        Spacer(minLength: KanalMetrics.md)
                        selectedValue
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(UIStrings.audioLanguage)
                            .font(KanalFont.caption(12))
                            .foregroundStyle(KanalColor.secondaryText)
                        selectedValue
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.audioLanguage")
            #else
            VStack(alignment: .leading, spacing: KanalMetrics.md) {
                Text(UIStrings.audioLanguage)
                    .font(KanalFont.caption(18))
                    .foregroundStyle(KanalColor.secondaryText)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: KanalMetrics.md) {
                        televisionLanguageButton(
                            String(UIStrings.audioLanguageOriginal),
                            value: nil
                        )
                        ForEach(codes, id: \.self) { code in
                            televisionLanguageButton(
                                AudioLanguagePreference.displayName(code),
                                value: code
                            )
                        }
                    }
                    .padding(.vertical, KanalMetrics.sm)
                }
                .scrollClipDisabled()
            }
            .accessibilityIdentifier("settings.audioLanguage")
            #endif
        } footer: {
            Text(footer)
        }
    }

    private var selectedValue: some View {
        HStack(spacing: 6) {
            Text(verbatim: selectedName)
                .font(KanalFont.body(15))
                .foregroundStyle(KanalColor.accentSolid)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(KanalColor.tertiaryText)
        }
    }

    private var selectedName: String {
        selection.map { AudioLanguagePreference.displayName($0) }
            ?? String(UIStrings.audioLanguageOriginal)
    }

    #if os(tvOS)
    private func televisionLanguageButton(_ name: String, value: String?) -> some View {
        Button {
            selection = value
        } label: {
            HStack(spacing: KanalMetrics.sm) {
                if selection == value {
                    Image(systemName: "checkmark")
                }
                Text(verbatim: name)
                    .lineLimit(1)
            }
            .foregroundStyle(selection == value ? Color.black : KanalColor.accentSolid)
            .padding(.horizontal, KanalMetrics.md)
        }
        .buttonStyle(.bordered)
        .tint(selection == value ? KanalColor.accentSolid : nil)
    }
    #endif
}
