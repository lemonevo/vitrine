## MODIFIED Requirements

### Requirement: Icon-only buttons SHALL have accessibility labels
Every `Button` whose visible content is only an `Image(systemName:)` SHALL have an `.accessibilityLabel` that describes the action. The label SHALL match the existing `.help()` tooltip text where one exists.

#### Scenario: VoiceOver announces gear button
- **WHEN** VoiceOver focus lands on the settings gear button in the sidebar toolbar
- **THEN** VoiceOver SHALL announce "Settings, button"

#### Scenario: VoiceOver announces copy button
- **WHEN** VoiceOver focus lands on a copy button in a field row
- **THEN** VoiceOver SHALL announce "Copy [field name], button" (e.g. "Copy Username, button")

#### Scenario: VoiceOver announces reveal button
- **WHEN** VoiceOver focus lands on a reveal/hide toggle on a masked field
- **THEN** VoiceOver SHALL announce "Reveal [field name], button" or "Hide [field name], button" depending on current state

#### Scenario: VoiceOver announces favorite button
- **WHEN** VoiceOver focus lands on the star button in the item header
- **THEN** VoiceOver SHALL announce "Favorite, button" or "Unfavorite, button" depending on current state

#### Scenario: VoiceOver announces new item button
- **WHEN** VoiceOver focus lands on the plus button in the content column toolbar
- **THEN** VoiceOver SHALL announce "New Item, pop up button"

#### Scenario: VoiceOver announces delete button on attachment row
- **WHEN** VoiceOver focus lands on a delete button on an attachment row
- **THEN** VoiceOver SHALL announce "Delete, button"

#### Scenario: VoiceOver announces open button on attachment row
- **WHEN** VoiceOver focus lands on an open button on an attachment row
- **THEN** VoiceOver SHALL announce "Open, button"

#### Scenario: VoiceOver announces refresh button in password generator
- **WHEN** VoiceOver focus lands on the refresh button in the password generator
- **THEN** VoiceOver SHALL announce "Generate new password, button"

#### Scenario: VoiceOver announces new folder button
- **WHEN** VoiceOver focus lands on the folder.badge.plus button in the sidebar
- **THEN** VoiceOver SHALL announce "New Folder, button"
