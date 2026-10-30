import UIKit
import AdjustSdk

/// Switches orientation support with the active launch destination.
@MainActor
enum OrientationLock {
    private(set) static var mask: UIInterfaceOrientationMask = .portrait

    static func portrait() {
        apply(.portrait)
    }

    static func allowPortraitAndLandscape() {
        apply(.allButUpsideDown)
    }

    private static func apply(_ newMask: UIInterfaceOrientationMask) {
        mask = newMask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: newMask)) { _ in }
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AdjustAttributionStore.shared.initialize()
        // Notification permission and Firebase setup are sequenced from the loading screen.
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistration.shared.receivedAPNS(deviceToken)
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
