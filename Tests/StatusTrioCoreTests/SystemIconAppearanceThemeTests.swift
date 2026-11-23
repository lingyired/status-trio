import Testing
@testable import StatusTrioCore

struct SystemIconAppearanceThemeTests {
    @Test func missingValueMeansDefault() {
        #expect(SystemIconAppearanceTheme.parse(nil) == .default)
        #expect(SystemIconAppearanceTheme.parse("") == .default)
    }

    @Test func parsesRegularStyles() {
        #expect(
            SystemIconAppearanceTheme.parse("RegularDark")
                == SystemIconAppearanceTheme(style: .defaultStyle, appearance: .dark)
        )
        #expect(
            SystemIconAppearanceTheme.parse("RegularAutomatic")
                == SystemIconAppearanceTheme(style: .defaultStyle, appearance: .automatic)
        )
    }

    @Test func parsesClearStyles() {
        #expect(
            SystemIconAppearanceTheme.parse("ClearLight")
                == SystemIconAppearanceTheme(style: .clear, appearance: .light)
        )
        #expect(
            SystemIconAppearanceTheme.parse("ClearDark")
                == SystemIconAppearanceTheme(style: .clear, appearance: .dark)
        )
        #expect(
            SystemIconAppearanceTheme.parse("ClearAutomatic")
                == SystemIconAppearanceTheme(style: .clear, appearance: .automatic)
        )
    }

    @Test func parsesTintedStyles() {
        #expect(
            SystemIconAppearanceTheme.parse("TintedDark")
                == SystemIconAppearanceTheme(style: .tinted, appearance: .dark)
        )
        #expect(
            SystemIconAppearanceTheme.parse("TintedAutomatic")
                == SystemIconAppearanceTheme(style: .tinted, appearance: .automatic)
        )
    }

    @Test func unknownValuesFallBackToDefault() {
        #expect(SystemIconAppearanceTheme.parse("SomethingNew") == .default)
        #expect(SystemIconAppearanceTheme.parse("regularDark") == .default)
    }

    @Test func readerUsesTheGlobalPreferenceValue() {
        var requestedKey: String?
        let theme = SystemIconAppearanceReader.current { key in
            requestedKey = key
            return "ClearDark"
        }

        #expect(requestedKey == SystemIconAppearanceReader.themeDefaultsKey)
        #expect(theme == SystemIconAppearanceTheme(style: .clear, appearance: .dark))
    }

    @Test func readerFallsBackToDefaultWhenUnavailable() {
        #expect(SystemIconAppearanceReader.current { _ in nil } == .default)
    }
}
