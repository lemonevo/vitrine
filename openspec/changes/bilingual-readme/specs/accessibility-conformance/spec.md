## REMOVED Requirements

### Requirement: Accessibility conformance statement SHALL exist at repo root

**Reason**: `ACCESSIBILITY.md` was deleted with the rest of the root document set on 2026-09-23. The
requirement mandated a file, so it cannot outlive one.

**What still holds**: the accessibility work itself, and it is asserted rather than described.
`AccessibilityTier2Tests` checks the direction of every `Opacity.*` function in
`Prizm/Presentation/ContrastAwareOpacity.swift`, and `ContrastTokenTests` does the alpha-compositing
arithmetic against the surfaces the panes actually paint — the two things the statement used to claim
in prose. VoiceOver labels and keyboard navigation are covered where they live, in the
`voiceover-labels` and `accessibility-contrast` capabilities.

**Migration**: none. The file is in git history (`git show 0014016:ACCESSIBILITY.md`).

### Requirement: Conformance statement SHALL be linked from README

**Reason**: As above — there is no statement to link to, and `README.md` carries no accessibility link.
The rationale for the link was discovery, and what a reader can still discover is the behaviour: the
accessibility bullets in the feature list, and a user interface that follows Reduce Motion and Increase
Contrast.

**Migration**: none.

### Requirement: Conformance statement SHALL document known gaps honestly

**Reason**: The requirement constrains a document that no longer exists. Its two scenarios named real
gaps — that WCAG 1.4.3 and 1.4.11 contrast had not been through a formal audit, and that drag-and-drop
folder operations have no keyboard-only alternative — but they asserted those gaps as *rows in a table*,
which is the part that cannot survive the table being deleted.

**What still holds**: both gaps are still true, and neither is now documented anywhere. That is a real
loss for an auditor and it is stated here rather than smoothed over. The second one is a code change
waiting to happen, not a documentation one.

**Migration**: none. If the project wants a conformance statement again, that is a new requirement.
