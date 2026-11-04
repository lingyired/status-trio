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

    init(
        selectedSection: SettingsView.Section = .appIcon,
        selectedSubtopic: SettingsSubtopic? = .appIconPlacementSize
    ) {
        self.selectedSection = selectedSection
        self.selectedSubtopic = selectedSubtopic
        self.expandedSection = selectedSection.hasSubtopics ? selectedSection : nil
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

    /// Selects one category. Simple categories just move the selection; an
    /// expandable category opens to its remembered or default leaf and collapses
    /// whichever category was expanded before.
    func select(_ section: SettingsView.Section) {
        selectedSection = section
        guard section.hasSubtopics else {
            expandedSection = nil
            selectedSubtopic = nil
            return
        }
        expandedSection = section
        let subtopic = lastSubtopicBySection[section] ?? defaultSubtopic(for: section)
        selectedSubtopic = subtopic
        if let subtopic {
            lastSubtopicBySection[section] = subtopic
        }
    }

    /// Selects a leaf and expands its parent.
    func selectSubtopic(_ subtopic: SettingsSubtopic) {
        selectedSection = subtopic.section
        expandedSection = subtopic.section
        selectedSubtopic = subtopic
        lastSubtopicBySection[subtopic.section] = subtopic
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
