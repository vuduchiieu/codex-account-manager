import Testing
@testable import LLMAccountSwitcher

struct LLMProviderTests {
    @Test func migratesLegacyGeminiProviderName() {
        #expect(LLMProvider.restore(storedValue: "gemini") == .antigravity)
        #expect(LLMProvider.restore(storedValue: "antigravity") == .antigravity)
        #expect(LLMProvider.restore(storedValue: "copilot") == .copilot)
    }
}
