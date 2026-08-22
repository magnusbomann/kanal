import KanalUI
import SwiftUI

@main
struct KanalApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // Anything AVFoundation cannot open is handed to VLC.
                .alternativePlayer { request in
                    AnyView(VLCPlaybackView(request: request).ignoresSafeArea())
                }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        #endif
    }
}
