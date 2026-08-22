import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// A QR code, rendered at whatever size it is given.
///
/// Generated at its native module size and scaled with nearest-neighbour
/// interpolation — smoothing the edges is what makes codes on a TV fail to
/// scan from across the room.
public struct QRCode: View {
    public let contents: String
    public var foreground: Color
    public var background: Color

    public init(
        contents: String,
        foreground: Color = .black,
        background: Color = .white
    ) {
        self.contents = contents
        self.foreground = foreground
        self.background = background
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            Group {
                if let image {
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .interpolation(.none)
                        .antialiased(false)
                } else {
                    Rectangle().fill(background)
                }
            }
            .frame(width: side, height: side)
            .background(background)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(Text(UIStrings.pairingCodeAccessibility))
    }

    private var image: CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(contents.utf8)
        // Medium correction: enough to survive a camera at an angle without
        // making the modules so dense they stop resolving on screen.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
