## REMOVED Requirements

### Requirement: Settings window opens via ⌘, and gear toolbar button

**Reason**: The gear button is gone from the vault browser's toolbar, and with it
`AccessibilityID.Vault.settingsButton`. The approved reference for the main window draws nothing
between the traffic lights and the sidebar toggle, and the gear was the one control in that strip the
picture does not have. It was also a second toolbar item competing with the browser's own controls for
the same row, in a window whose subject is not settings.

**What still holds**: the other half of the requirement is untouched. The settings window is still a
SwiftUI `Settings` scene, it still opens with ⌘,, and it is still a separate native window — the
scenarios for those keep passing with the menu route as the only route.

**Migration**: open Settings from the app menu (⌘,), or from any future entry point the settings work
adds. Restoring the button means re-adding a `ToolbarItem` to the sidebar column, restoring the
identifier, and repointing `AccessibilityLabelTests.testSyncButtonHasLabel`'s predecessor — that test
used to reach the gear and now checks the sync control, the browser's remaining icon-only button.
