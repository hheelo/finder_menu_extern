import Foundation

enum OnboardingPollingPolicy {
    static let maximumDuration = Duration.seconds(5 * 60)

    static func nextPollInterval(attempt: Int) -> Duration {
        switch attempt {
        case ..<5:
            .seconds(1)
        case ..<15:
            .seconds(2)
        default:
            .seconds(5)
        }
    }
}
