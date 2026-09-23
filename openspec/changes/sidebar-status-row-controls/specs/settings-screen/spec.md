## ADDED Requirements

### Requirement: Settings opens from the sidebar, as well as from the app menu

The vault browser SHALL reach the Settings window from two places: the app menu's Settings item (⌘,),
and a gear control at the **trailing end of the sidebar's status row**. Both SHALL resolve the same
`Settings` scene, so that there is one Settings window rather than two entry points which can disagree
about which one it is.

The gear SHALL carry an accessibility label — it is an icon-only control, so the label is the only
thing that names it — and it SHALL be drawn at the muted foreground. Settings is not what that row is
about, and a control drawn at the weight of the sync status would compete with the one piece of
information the row exists to carry.

**Why this is not the toolbar button the canonical spec describes.** That requirement, "Settings window
opens via ⌘, and gear toolbar button", with a scenario placing the gear "next to the search field", was
removed by `main-window-p3-pass`: the approved reference for the main window draws nothing between the
traffic lights and the sidebar toggle. This requirement puts the control somewhere the reference does
not legislate, and it is written under a new heading rather than as a modification so that a removal
and an addition do not have to be reconciled at archive time.

#### Scenario: The gear opens Settings

- **WHEN** the user clicks the gear at the trailing end of the sidebar's status row
- **THEN** the Settings window opens

#### Scenario: Both routes reach one window

- **GIVEN** the Settings window is already open
- **WHEN** the user takes the other route to it
- **THEN** that window is brought forward, rather than a second one being created

#### Scenario: The gear is named for assistive technology

- **WHEN** the sidebar's status row is inspected with VoiceOver
- **THEN** the gear announces itself as "Settings"
