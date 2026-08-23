import KanalCore
import SwiftUI

/// The four-digit challenge.
///
/// Drawn as an explicit number pad rather than a text field. A `TextField` with
/// a number keypad works on iPhone and is unusable on a television, and this
/// screen has to be the same thing on both — it is the one interaction where a
/// parent needs to know exactly what they are looking at.
public struct ParentalCodeView: View {

    public enum Purpose {
        /// Prove you are a grown-up.
        case unlock
        /// Choose a new code, typed twice.
        case set

        var titleResource: LocalizedStringResource {
            switch self {
            case .unlock: UIStrings.codeEnterTitle
            case .set: UIStrings.codeSetTitle
            }
        }

        var messageResource: LocalizedStringResource {
            switch self {
            case .unlock: UIStrings.codeEnterMessage
            case .set: UIStrings.codeSetMessage
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    public let purpose: Purpose
    /// Returns whether the code was accepted. A `false` shakes the dots and
    /// clears them; the sheet stays up.
    public let onSubmit: (String) -> Bool

    @State private var entered = ""
    @State private var confirming: String?
    @State private var isWrong = false
    @State private var shake = 0

    public init(purpose: Purpose, onSubmit: @escaping (String) -> Bool) {
        self.purpose = purpose
        self.onSubmit = onSubmit
    }

    public var body: some View {
        VStack(spacing: KanalMetrics.lg) {
            Spacer(minLength: 0)

            Image(systemName: "lock.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(KanalColor.accentSolid)

            VStack(spacing: KanalMetrics.xs) {
                Text(title)
                    .font(KanalFont.section(20))
                    .foregroundStyle(KanalColor.primaryText)
                Text(message)
                    .font(KanalFont.body(14))
                    .foregroundStyle(KanalColor.secondaryText)
                    .multilineTextAlignment(.center)
            }

            dots
                .modifier(ShakeEffect(animatableData: CGFloat(shake)))

            pad

            Button(String(UIStrings.cancel)) { dismiss() }
                .buttonStyle(KanalSecondaryButtonStyle(size: 14))

            Spacer(minLength: 0)
        }
        .padding(KanalMetrics.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KanalColor.background)
    }

    private var title: String {
        if confirming != nil { return String(UIStrings.codeConfirmTitle) }
        return String(purpose.titleResource)
    }

    private var message: String {
        if confirming != nil { return String(UIStrings.codeConfirmMessage) }
        if isWrong { return String(UIStrings.codeWrong) }
        return String(purpose.messageResource)
    }

    private var dots: some View {
        HStack(spacing: KanalMetrics.md) {
            ForEach(0..<ParentalCode.length, id: \.self) { index in
                Circle()
                    .fill(index < entered.count ? KanalColor.accentSolid : KanalColor.separator)
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.vertical, KanalMetrics.sm)
        .accessibilityLabel(Text(UIStrings.codeDigitsEntered(entered.count)))
    }

    private var pad: some View {
        VStack(spacing: KanalMetrics.sm) {
            ForEach(rows, id: \.first) { row in
                HStack(spacing: KanalMetrics.sm) {
                    ForEach(row, id: \.self) { key in
                        padButton(key)
                    }
                }
            }
        }
    }

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]]

    @ViewBuilder
    private func padButton(_ key: String) -> some View {
        if key.isEmpty {
            Color.clear.frame(width: keySize, height: keySize)
        } else {
            Button {
                press(key)
            } label: {
                Text(verbatim: key)
                    .font(KanalFont.section(22))
                    .foregroundStyle(KanalColor.primaryText)
                    .frame(width: keySize, height: keySize)
                    .kanalGlassPill()
            }
            .buttonStyle(.plain)
        }
    }

    private var keySize: CGFloat {
        #if os(tvOS)
        96
        #else
        64
        #endif
    }

    private func press(_ key: String) {
        isWrong = false
        if key == "⌫" {
            if !entered.isEmpty { entered.removeLast() }
            return
        }
        guard entered.count < ParentalCode.length else { return }
        entered.append(key)
        guard entered.count == ParentalCode.length else { return }

        switch purpose {
        case .unlock:
            finish(with: entered)

        case .set:
            // Typed twice. A code entered once and mistyped locks a parent out
            // of their own app with no way back short of reinstalling.
            if let first = confirming {
                if first == entered {
                    finish(with: entered)
                } else {
                    confirming = nil
                    reject()
                }
            } else {
                confirming = entered
                entered = ""
            }
        }
    }

    private func finish(with code: String) {
        if onSubmit(code) {
            dismiss()
        } else {
            reject()
        }
    }

    private func reject() {
        entered = ""
        isWrong = true
        withAnimation(.default) { shake += 1 }
    }
}

/// The sideways nudge that says "no" without a word of copy.
private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0)
        )
    }
}
