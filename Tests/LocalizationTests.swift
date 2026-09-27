import Testing
@testable import LLMAccountSwitcher

struct LocalizationTests {
    @Test func choosesFirstSupportedSystemLanguage() {
        #expect(AppLanguage.preferred(from: ["vi-VN"]) == .vietnamese)
        #expect(AppLanguage.preferred(from: ["en-US"]) == .english)
        #expect(AppLanguage.preferred(from: ["ja-JP"]) == .japanese)
        #expect(AppLanguage.preferred(from: ["zh-Hant-TW"]) == .chinese)
        #expect(AppLanguage.preferred(from: ["fr-FR", "ja-JP"]) == .japanese)
        #expect(AppLanguage.preferred(from: ["fr-FR"]) == .english)
    }

    @Test func everyLanguageContainsEveryEnglishKey() {
        for language in [AppLanguage.vietnamese, .english, .japanese, .chinese] {
            #expect(L10n.missingKeys(for: language).isEmpty)
        }
    }

    @Test func formatsLocalizedValues() {
        #expect(L10n.text("add_account", language: .vietnamese) == "Thêm tài khoản")
        #expect(L10n.text("add_account", language: .english) == "Add Account")
        #expect(L10n.text("add_account", language: .japanese) == "アカウントを追加")
        #expect(L10n.text("add_account", language: .chinese) == "添加账号")
        #expect(L10n.format("remaining", language: .english, arguments: [42]) == "42% left")
    }
}
