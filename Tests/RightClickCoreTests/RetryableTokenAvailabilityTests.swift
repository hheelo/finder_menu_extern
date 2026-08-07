import Testing
@testable import RightClickCore

struct RetryableTokenAvailabilityTests {
    @Test
    func retriesAfterFailureAndCachesSuccess() {
        var availability = RetryableTokenAvailability()
        var attempts = 0
        let token = ExtensionRequestTokenStore.makeToken()

        let first = availability.current {
            attempts += 1
            throw TestError.unavailable
        }
        let second = availability.current {
            attempts += 1
            return token
        }
        let third = availability.current {
            attempts += 1
            return ExtensionRequestTokenStore.makeToken()
        }

        #expect(first == nil)
        #expect(second == token)
        #expect(third == token)
        #expect(attempts == 2)
    }
}

private enum TestError: Error {
    case unavailable
}
