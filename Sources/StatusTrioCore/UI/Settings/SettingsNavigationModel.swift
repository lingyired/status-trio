import Foundation

/// The single source of truth for the Settings sidebar's two-level selection.
///
/// One category is selected at a time and, if it is an expandable category,
/// exactly one of its leaf subtopics is selected underneath it. Keeping this in
/// one small model (instead of several independent `@State` values) makes the
/// parent/leaf relationship explicit and lets the routing rules be unit-tested
/// without hosting a window.
@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published private(set) var selectedSection: SettingsView.Section
    @Published private(set) var expandedSection: SettingsView.Section?
    @Published private(set) var selectedSubtopic: SettingsSubtopic?

    /// Remembers the leaf the user last looked at per category, so re-entering a
    /// category returns to that page instead of always jumping to the default.
    private var lastSubtopicBySection: [SettingsView.Section: SettingsSubtopic]

    /// The category with leaves. Only App Icon has submenus now, so its children
    /// stay visible at all times; selecting another category must not collapse
    /// it. Computed rather than hard-coded so it keeps working if another
    /// expandable category is ever added back.
    private static var alwaysExpandedSection: SettingsView.Section? {
        SettingsView.Section.allCases.first { $0.hasSubtopics }
    }

    init(
        selectedSection: SettingsView.Section = .appIcon,
        selectedSubtopic: SettingsSubtopic? = .appIconAppearance
    ) {
        self.selectedSection = selectedSection
        self.selectedSubtopic = selectedSubtopic
        self.expandedSection = Self.alwaysExpandedSection
        var remembered: [SettingsView.Section: SettingsSubtopic] = [:]
        if let selectedSubtopic {
            remembered[selectedSection] = selectedSubtopic
        }
        self.lastSubtopicBySection = remembered
    }

    /// The leaves shown under a category, in their fixed sidebar order.
    func subtopics(for section: SettingsView.Section) -> [SettingsSubtopic] {
        section.subtopics
    }

    func defaultSubtopic(for section: SettingsView.Section) -> SettingsSubtopic? {
        section.subtopics.first { $0.isDefault } ?? section.subtopics.first
    }

    /// Selects one category. Simple categories just move the selection; the one
    /// expandable category (App Icon) opens to its remembered or default leaf.
    /// It never collapses, because it is now the only category with a submenu.
    func select(_ section: SettingsView.Section) {
        let nextSubtopic: SettingsSubtopic?
        if section.hasSubtopics {
            nextSubtopic = lastSubtopicBySection[section] ?? defaultSubtopic(for: section)
        } else {
            nextSubtopic = nil
        }
        if let nextSubtopic {
            lastSubtopicBySection[section] = nextSubtopic
        }
        applySelection(section: section, subtopic: nextSubtopic)
    }

    /// Selects a leaf inside its parent category.
    func selectSubtopic(_ subtopic: SettingsSubtopic) {
        lastSubtopicBySection[subtopic.section] = subtopic
        applySelection(section: subtopic.section, subtopic: subtopic)
    }

    /// Assigns only the fields that actually change, so re-clicking the current
    /// row does not publish an object change and rebuild the detail page for
    /// nothing. The expandable section is pinned open.
    private func applySelection(
        section: SettingsView.Section,
        subtopic: SettingsSubtopic?
    ) {
        if selectedSection != section {
            selectedSection = section
        }
        let pinned = Self.alwaysExpandedSection
        if expandedSection != pinned {
            expandedSection = pinned
        }
        if selectedSubtopic != subtopic {
            selectedSubtopic = subtopic
        }
    }

    /// Applies a deep link from the status panel or another window action.
    /// A leaf that does not belong to the requested category is ignored, so a
    /// stale request can never render the wrong page.
    func apply(section: SettingsView.Section, subtopic: SettingsSubtopic?) {
        if let subtopic, subtopic.section == section, section.hasSubtopics {
            selectSubtopic(subtopic)
        } else {
            select(section)
        }
    }
}

extension SettingsView.Section {
    /// The leaves beneath this category; empty for the five single-pane pages.
    var subtopics: [SettingsSubtopic] {
        SettingsSubtopic.allCases.filter { $0.section == self }
    }

    /// True only for the categories that open a second sidebar level.
    var hasSubtopics: Bool {
        !subtopics.isEmpty
    }
}
