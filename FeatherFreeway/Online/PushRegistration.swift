import UIKit
import UserNotifications
#if canImport(FirebaseMessaging)
import FirebaseCore
import FirebaseMessaging
#endif

@MainActor
final class PushRegistration: NSObject {
    static let shared = PushRegistration()
    private var token: String?
    private var configured = false

    /// Ask while the loading screen is visible, then configure Firebase and register for APNs.
    /// The caller awaits this method so launch API requests cannot start before the prompt closes.
    func requestPermissionAndRegister() async {
        #if canImport(FirebaseMessaging)
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        guard !configured else {
            UIApplication.shared.registerForRemoteNotifications()
            return
        }
        // Tracked locally: FirebaseApp.app() logs an error when called before configure().
        FirebaseApp.configure()
        configured = true
        Messaging.messaging().delegate = self
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }
    func receivedAPNS(_ value: Data) {
        #if canImport(FirebaseMessaging)
        guard configured else { return }
        Messaging.messaging().apnsToken = value
        Messaging.messaging().token { [weak self] value, _ in
            Task { @MainActor [weak self] in self?.token = value }
        }
        #endif
    }
    func tokenWithinThreeSeconds() async -> String {
        let deadline = ContinuousClock.now + .seconds(3)
        while token == nil && ContinuousClock.now < deadline && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return token ?? ""
    }
}
#if canImport(FirebaseMessaging)
extension PushRegistration: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in self.token = fcmToken }
    }
}
#endif
