import Foundation
import Testing

struct OnboardingPollingPolicyTests {
    @Test
    func pollingBacksOffAndHasAFiveMinuteLimit() {
        #expect(OnboardingPollingPolicy.nextPollInterval(attempt: 0) == .seconds(1))
        #expect(OnboardingPollingPolicy.nextPollInterval(attempt: 4) == .seconds(1))
        #expect(OnboardingPollingPolicy.nextPollInterval(attempt: 5) == .seconds(2))
        #expect(OnboardingPollingPolicy.nextPollInterval(attempt: 14) == .seconds(2))
        #expect(OnboardingPollingPolicy.nextPollInterval(attempt: 15) == .seconds(5))
        #expect(OnboardingPollingPolicy.nextPollInterval(attempt: 10_000) == .seconds(5))
        #expect(OnboardingPollingPolicy.maximumDuration == .seconds(300))
    }
}
