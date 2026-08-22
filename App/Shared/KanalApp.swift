import KanalUI
import SwiftUI

@main
struct KanalApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        #endif
    }
}
