#if os(iOS)
import UIKit

/// The television, when the phone is mirrored to one.
///
/// AirPlay's own video path belongs to `AVPlayer`, and VLC — which plays
/// nearly every film a real provider serves — has no part in it. Picking an
/// Apple TV from the route picker therefore moves only the sound. What does
/// reach VLC is screen mirroring: iOS offers the mirrored screen to the app as
/// a scene of its own, and drawing the film into that scene is what puts the
/// picture on the television, full size, while the phone keeps the controls.
@MainActor
final class ExternalDisplay {
    static let shared = ExternalDisplay()
    static let didChange = Notification.Name("Kanal.ExternalDisplay.didChange")

    /// The view on the television, while there is one.
    private(set) var surface: UIView?

    func connect(_ view: UIView) {
        surface = view
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func disconnect() {
        surface = nil
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

/// Declared in Info.plist for the external display role. The rest of the app
/// stays SwiftUI; this only owns the mirrored screen.
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let scene = scene as? UIWindowScene else { return }
        let controller = UIViewController()
        controller.view.backgroundColor = .black

        // Something other than black while nothing plays, so a mirrored
        // television does not look broken between films.
        let mark = UILabel()
        mark.text = "Kanal"
        mark.font = .systemFont(ofSize: 56, weight: .heavy)
        mark.textColor = UIColor.white.withAlphaComponent(0.25)
        mark.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(mark)
        NSLayoutConstraint.activate([
            mark.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
        ])

        let surface = UIView()
        surface.backgroundColor = .clear
        surface.frame = controller.view.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(surface)

        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.isHidden = false
        self.window = window
        MainActor.assumeIsolated { ExternalDisplay.shared.connect(surface) }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
        MainActor.assumeIsolated { ExternalDisplay.shared.disconnect() }
    }
}
#endif
