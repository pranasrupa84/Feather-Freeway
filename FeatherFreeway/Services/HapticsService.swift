import UIKit

/// Thin wrapper around UIKit feedback generators that respects the haptics setting.
@MainActor
final class HapticsService {
    enum Impact {
        case light, medium, heavy
    }

    enum Outcome {
        case success, warning, error

        fileprivate var feedbackType: UINotificationFeedbackGenerator.FeedbackType {
            switch self {
            case .success: .success
            case .warning: .warning
            case .error: .error
            }
        }
    }

    private let isEnabled: () -> Bool
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()

    /// A service that never vibrates. Used in tests and previews.
    static let silent = HapticsService { false }

    init(isEnabled: @escaping () -> Bool) {
        self.isEnabled = isEnabled
    }

    func prepare() {
        guard isEnabled() else { return }
        lightGenerator.prepare()
        mediumGenerator.prepare()
    }

    func impact(_ impact: Impact) {
        guard isEnabled() else { return }
        switch impact {
        case .light: lightGenerator.impactOccurred()
        case .medium: mediumGenerator.impactOccurred()
        case .heavy: heavyGenerator.impactOccurred()
        }
    }

    func notify(_ outcome: Outcome) {
        guard isEnabled() else { return }
        notificationGenerator.notificationOccurred(outcome.feedbackType)
    }

    func selection() {
        guard isEnabled() else { return }
        selectionGenerator.selectionChanged()
    }
}
