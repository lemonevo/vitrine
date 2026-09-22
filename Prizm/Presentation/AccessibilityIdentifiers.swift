import Foundation

/// Centralized accessibility identifiers used by SwiftUI views and XCUITests.
///
/// Keeping identifiers in a single namespace avoids typos and makes refactoring safer.
/// Both the main app target and the UI test target reference this enum.
nonisolated enum AccessibilityID {

    // MARK: - Login (US1)

    enum Login {
        static let serverURLField    = "login.serverURL"
        static let emailField        = "login.email"
        static let passwordField     = "login.password"
        static let signInButton      = "login.signIn"
        static let errorMessage      = "login.error"
        static let headerTitle       = "login.headerTitle"
    }

    // MARK: - Two-factor (US1)

    /// The prompt is one screen for every method, so these names say "twoFactor" rather than
    /// "totp" — an emailed code is not a TOTP code. `Prizm/UITests/LoginJourneyTests.swift`
    /// queries them by string and was updated with them.
    enum TwoFactor {
        static let codeField         = "twoFactor.code"
        static let rememberToggle    = "twoFactor.remember"
        static let continueButton    = "twoFactor.continue"
        static let cancelButton      = "twoFactor.cancel"
        static let errorMessage      = "twoFactor.error"
        static let headerTitle       = "twoFactor.headerTitle"
        static let methodName        = "twoFactor.method"
        static let resendButton      = "twoFactor.resend"
    }

    // MARK: - Sync Progress

    enum Sync {
        static let progressMessage   = "sync.progressMessage"
    }

    // MARK: - Unlock (US2)

    enum Unlock {
        static let passwordField     = "unlock.password"
        /// The PIN entry, offered only when the repository says a PIN may open this launch.
        static let pinField              = "unlock.pin"
        /// Shown only after a wrong PIN — a bare count on arrival reads as a threat.
        static let pinAttemptsRemaining  = "unlock.pinAttemptsRemaining"
        /// Switches the single credential field between the PIN and the master password.
        static let switchCredential      = "unlock.switchCredential"
        static let unlockButton      = "unlock.unlock"
        static let errorMessage      = "unlock.error"
        static let headerTitle       = "unlock.headerTitle"
        static let switchAccount     = "unlock.switchAccount"
        /// The button that raises the system Touch ID / Face ID prompt.
        static let biometricButton   = "unlock.biometricButton"
        static let enrollmentPrompt  = "unlock.enrollmentPrompt"
    }

    // MARK: - Vault Browser (US3)

    enum Vault {
        static let navigationSplit   = "vault.navigationSplit"
        static let syncStatusLabel   = "vault.syncStatus"
        /// The sidebar's standing report of items the last sync could not read. Distinct from
        /// `syncStatusLabel`: this one is not dismissable, because the condition it describes
        /// outlives the message.
        static let unreadableItemsLabel = "vault.unreadableItems"
        /// The secure-note subtype picker in the edit sheet.
        static let itemEditNoteSubtype   = "vault.edit.noteSubtype"
        static let itemEditCardBrand     = "vault.edit.cardBrand"
        static let itemEditCardExpMonth  = "vault.edit.cardExpMonth"
        static let itemEditCardExpYear   = "vault.edit.cardExpYear"
        static let syncErrorBanner   = "vault.syncErrorBanner"
        static let syncErrorDismiss  = "vault.syncErrorDismiss"
        /// The JSON/CSV choice on the export consent sheet.
        static let formatPicker     = "vault.backup.exportFormat"
        /// The line naming how many items the chosen format could not carry.
        static let omittedCount     = "vault.backup.omittedCount"
        /// The toolbar button opening the vault-wide verification-codes list.
        static let verificationCodesButton = "vault.verificationCodes"
        /// The manual sync button at the end of the sidebar's status row (⌘R).
        static let syncButton        = "vault.button.sync"
        /// The sort-order menu at the window's trailing edge.
        static let sortMenu          = "vault.menu.sort"
    }

    // MARK: - Sidebar (US3)

    enum Sidebar {
        static let list              = "sidebar.list"
        static let allItems          = "sidebar.allItems"
        static let favorites         = "sidebar.favorites"
        static let trash             = "sidebar.trash"
        static func type(_ name: String) -> String { "sidebar.type.\(name)" }
    }

    // MARK: - Item List (US3)

    enum ItemList {
        static let list              = "itemList.list"
        static let emptyState        = "itemList.empty"
        /// The "Duplicate" entry in a row's context menu.
        static let duplicateAction   = "itemList.action.duplicate"
        static func row(_ id: String) -> String { "itemList.row.\(id)" }
    }

    // MARK: - Item Detail (US3)

    enum Detail {
        static let emptyState        = "detail.empty"
        static let itemName          = "detail.name"
        /// The line under the item's name: username · folder · organisation.
        static let breadcrumb        = "detail.breadcrumb"
        /// The header's favourite control, which moved here from the window toolbar.
        static let favoriteToggle    = "detail.favorite"
        /// The single relative/absolute date line at the foot of the pane.
        static let metaLine          = "detail.meta"
        /// The header's action row. These are the copy paths a re-prompt gate has to cover, so a
        /// test needs to reach them without depending on their labels, which are localised.
        static let copyPasswordButton = "detail.action.copyPassword"
        static let copyCodeButton     = "detail.action.copyCode"
        static let openWebsiteButton  = "detail.action.openWebsite"
        /// Accessibility identifier for a `DetailSectionCard` header label.
        static func cardHeader(_ title: String) -> String {
            "detail.cardHeader.\(title.lowercased().replacingOccurrences(of: " ", with: "."))"
        }
    }

    // MARK: - Field Row (US3)

    enum Field {
        static func row(_ label: String) -> String { "field.\(label)" }
        static func copyButton(_ label: String) -> String { "field.\(label).copy" }
        static func revealButton(_ label: String) -> String { "field.\(label).reveal" }
        static func openButton(_ label: String) -> String { "field.\(label).open" }
    }

    // MARK: - Masked Field (US3)

    enum Masked {
        static func value(_ label: String) -> String { "masked.\(label).value" }
        static func toggle(_ label: String) -> String { "masked.\(label).toggle" }
    }

    // MARK: - Item Edit (edit-vault-items)

    enum Reprompt {
        /// The item name shown in the master-password re-prompt sheet.
        static let itemName       = "reprompt.itemName"
        /// The master-password field in the re-prompt sheet.
        static let passwordField  = "reprompt.passwordField"
        /// The inline error shown after a wrong master password.
        static let error          = "reprompt.error"
        /// The Cancel button — the only way out of the sheet that grants nothing.
        static let cancelButton   = "reprompt.button.cancel"
        /// The Confirm button.
        static let confirmButton  = "reprompt.button.confirm"
    }

    // MARK: - SSH agent (ssh-agent)

    enum SSHAgent {
        /// The key name and requesting process shown in the signature-request sheet.
        static let requestDescription = "sshAgent.requestDescription"
        /// The master-password field in the signature-request sheet.
        static let passwordField      = "sshAgent.passwordField"
        /// The inline error shown after a wrong master password.
        static let error              = "sshAgent.error"
        /// The Cancel button — the only way out of the sheet that grants nothing.
        static let cancelButton       = "sshAgent.button.cancel"
        /// The Confirm button.
        static let confirmButton      = "sshAgent.button.confirm"

        // The Settings pane. Prefixed apart from the sheet's, because both can be on screen at once
        // and an identifier that matched two controls would be worse than none.
        static let settingsToggle  = "sshAgent.settings.toggle"
        /// The one line saying what the agent is doing, or why it is not.
        static let status          = "sshAgent.settings.status"
        static let socketPath      = "sshAgent.settings.socketPath"
        static let copySocket      = "sshAgent.settings.copySocket"
        static let exportLine      = "sshAgent.settings.exportLine"
        static let copyExportLine  = "sshAgent.settings.copyExportLine"
        /// Shown when the vault holds no SSH keys at all.
        static let noKeys          = "sshAgent.settings.noKeys"
        static let usableKey       = "sshAgent.settings.usableKey"
        static let unusableKey     = "sshAgent.settings.unusableKey"
    }

    /// The PIN settings and the set-PIN sheet.
    ///
    /// A namespace of its own because the sheet can be on screen over the pane, and an identifier
    /// matching two controls is worse than none.
    enum PinSettings {
        static let toggle                  = "pinSettings.toggle"
        static let requirePasswordOnRestart = "pinSettings.requirePasswordOnRestart"
        static let pinEntry                = "pinSettings.entry"
        static let pinConfirmation         = "pinSettings.confirmation"
        static let pinConfirm              = "pinSettings.confirm"
        static let pinCancel               = "pinSettings.cancel"
    }

    /// The verification-codes list and its rows.
    enum VerificationCodes {
        static let sheet       = "verificationCodes.sheet"
        static let emptyState  = "verificationCodes.empty"
        static let doneButton  = "verificationCodes.done"
        static func row(_ id: String) -> String { "verificationCodes.row.\(id)" }
        static func copyButton(_ id: String) -> String { "verificationCodes.copy.\(id)" }
        static func revealButton(_ id: String) -> String { "verificationCodes.reveal.\(id)" }
    }

    // MARK: - TOTP code display (totp-code-display)

    /// The one-time-code row in the login detail view.
    ///
    /// `maskedValue` and `value` are separate identifiers rather than one with a changing label,
    /// because which of the two is present *is* the assertion a test wants to make: the row is
    /// masked by default, and revealing swaps one element for the other.
    enum TOTP {
        static let row          = "totp.row"
        /// The grouped code, present only while revealed.
        static let value        = "totp.value"
        /// The bullet placeholder, present only while masked.
        static let maskedValue  = "totp.maskedValue"
        /// The seconds remaining, present only while revealed.
        static let countdown    = "totp.countdown"
        static let revealButton = "totp.reveal"
        /// Shown in place of the code when the stored key produces none.
        static let unusable     = "totp.unusable"
    }

    // MARK: - Account fingerprint (account-fingerprint)

    enum Fingerprint {
        static let phrase = "fingerprint.phrase"
        static let copy   = "fingerprint.copy"
        static let note   = "fingerprint.note"
    }

    enum ServerTrust {
        static let pinningToggle      = "serverTrust.toggle.pinning"
        static let fingerprint        = "serverTrust.fingerprint"
        static let authorityCount     = "serverTrust.authorityCount"
        static let trustButton        = "serverTrust.button.trust"
        static let forgetPinButton    = "serverTrust.button.forgetPin"
        static let stopTrustingButton = "serverTrust.button.stopTrusting"
        static let error              = "serverTrust.error"
        /// Shown instead of the controls when no server is configured yet.
        static let noHost             = "serverTrust.noHost"
    }

    enum Edit {
        /// The "Edit" toolbar button in ItemDetailView.
        static let editButton    = "edit.button.edit"
        /// The "Save" / "Saving…" button in ItemEditView.
        static let saveButton    = "edit.button.save"
        /// The "Discard" button in ItemEditView.
        static let discardButton = "edit.button.discard"
        /// The "Delete Item" button in ItemEditView (edit mode only).
        static let deleteButton  = "edit.button.delete"
        /// The inline error banner shown on save failure.
        static let errorBanner   = "edit.errorBanner"
        /// The strength readout under the Login password field.
        static let passwordStrength = "edit.passwordStrength"
        /// The warning under the TOTP seed field, drawn only when the value will not produce a code.
        static let totpSeedWarning  = "edit.totpSeedWarning"
        /// The "Master password re-prompt" toggle, present for every item type.
        static let repromptToggle   = "edit.toggle.reprompt"
        /// The "Add Field" button in the custom-fields section.
        static let addCustomFieldButton = "edit.button.addCustomField"
        /// A custom-field row; `id` is the draft field's stable UUID.
        static func customFieldRow(_ id: String) -> String { "edit.customField.\(id)" }
        /// The delete button on a custom-field row.
        static func customFieldDelete(_ id: String) -> String { "edit.customField.\(id).delete" }
        /// The move-up button on a custom-field row.
        static func customFieldMoveUp(_ id: String) -> String { "edit.customField.\(id).up" }
        /// The move-down button on a custom-field row.
        static func customFieldMoveDown(_ id: String) -> String { "edit.customField.\(id).down" }
    }

    // MARK: - Trash (delete-restore-items)

    enum Trash {
        /// The empty-state view shown when Trash contains no items.
        static let emptyState        = "trash.emptyState"
        /// The banner shown in ItemDetailView when the selected item is in trash.
        static let statusBanner      = "trash.statusBanner"
        /// The "Restore" toolbar button in ItemDetailView for trashed items.
        static let restoreButton     = "trash.button.restore"
        /// The "Delete Permanently" toolbar button in ItemDetailView for trashed items.
        static let permanentDeleteButton = "trash.button.permanentDelete"
        /// The "Empty Trash" button in the Trash view.
        static let emptyTrashButton      = "trash.button.empty"
        static let retentionNotice = "trash.retentionNotice"
    }

    // MARK: - Create Item (add-vault-items)

    enum Create {
        /// The "+" button that opens the new-item type picker popover.
        static let newItemButton = "create.button.newItem"
    }

    // MARK: - Attachments (vault-document-storage)

    enum Attachment {
        /// The Attachments section card in ItemDetailView.
        static let sectionCard = "attachment.section"
        /// The "Add Attachment" button in the Attachments section card.
        static let addButton   = "attachment.button.add"
        /// An attachment row; `id` is the server-assigned attachment ID.
        static func row(_ id: String) -> String { "attachment.row.\(id)" }
        /// The Open button on a specific attachment row.
        static func openButton(_ id: String) -> String { "attachment.row.\(id).open" }
        /// The Save to Disk button on a specific attachment row.
        static func saveButton(_ id: String) -> String { "attachment.row.\(id).save" }
        /// The Delete button on a specific attachment row.
        static func deleteButton(_ id: String) -> String { "attachment.row.\(id).delete" }
        /// The Retry Upload button shown when `isUploadIncomplete` is true.
        static func retryButton(_ id: String) -> String { "attachment.row.\(id).retry" }
    }

    // MARK: - Password Generator (password-generator)

    enum Generator {
        static let modePicker          = "generator.modePicker"
        static let lengthSlider        = "generator.lengthSlider"
        static let uppercaseToggle     = "generator.toggle.uppercase"
        static let lowercaseToggle     = "generator.toggle.lowercase"
        static let digitsToggle        = "generator.toggle.digits"
        static let symbolsToggle       = "generator.toggle.symbols"
        static let avoidAmbiguousToggle = "generator.toggle.avoidAmbiguous"
        static let wordCountStepper    = "generator.wordCount"
        static let usernameWordCountStepper = "generator.username.wordCount"
        static let usernameIncludeNumberToggle = "generator.username.includeNumber"
        static let separatorField      = "generator.separator"
        static let capitalizeToggle    = "generator.toggle.capitalize"
        static let includeNumberToggle = "generator.toggle.includeNumber"
        static let preview             = "generator.preview"
        static let refreshButton       = "generator.button.refresh"
        static let copyButton          = "generator.button.copy"
        static let useButton           = "generator.button.use"
        static let triggerButton       = "generator.button.trigger"
        /// The strength readout under the generated value.
        static let strengthReadout     = "generator.strengthReadout"
        /// The collapsible session-history section.
        static let historySection      = "generator.history"
        /// The copy button on a history row; `index` is the row's position, newest first.
        static func historyCopyButton(_ index: Int) -> String { "generator.history.copy.\(index)" }
    }

    // MARK: - Password History (password-history-view)

    enum PasswordHistory {
        static let section      = "passwordHistory.section"
        /// The entry count in the disclosure label. Absent until the section has been opened once.
        static let countBadge   = "passwordHistory.count"
        static let progress     = "passwordHistory.progress"
        static let errorMessage = "passwordHistory.error"
        static let emptyState   = "passwordHistory.empty"
        /// The footnote explaining that revealing requires the master password.
        static let revealNote   = "passwordHistory.revealNote"

        /// The masked value of one entry; `index` is its position, newest first.
        static func value(_ index: Int) -> String { "passwordHistory.value.\(index)" }
        static func copyButton(_ index: Int) -> String { "passwordHistory.copy.\(index)" }
        /// The reveal toggle for one entry — the one disclosure here that the gate stands in
        /// front of. Absent until wave C; the wave B build only ever masked these values.
        static func revealButton(_ index: Int) -> String { "passwordHistory.reveal.\(index)" }
    }

    // MARK: - Passkeys (passkey-viewer)

    enum Passkeys {
        static let section      = "passkeys.section"
        /// The credential count in the disclosure label. Absent until the section has been opened.
        static let countBadge   = "passkeys.count"
        static let progress     = "passkeys.progress"
        static let errorMessage = "passkeys.error"
        static let emptyState   = "passkeys.empty"
        /// The footnote saying these cannot be used here. Not optional: without it the list reads
        /// as a feature that failed rather than one that is intentionally read-only.
        static let limitationNote = "passkeys.limitationNote"

        static func rpId(_ index: Int)     -> String { "passkeys.rpId.\(index)" }
        static func userName(_ index: Int) -> String { "passkeys.userName.\(index)" }
        static func date(_ index: Int)     -> String { "passkeys.date.\(index)" }
    }

    // MARK: - Vault Health Report (vault-health-report)

    enum Health {
        static let sheet         = "health.sheet"
        /// The green "all five checks passed" banner.
        static let cleanBanner   = "health.banner.clean"
        /// The amber "n issues found" banner. Distinct from `cleanBanner` so a test can tell the two
        /// apart without reading the text, which changes with the language.
        static let summaryBanner = "health.banner.summary"
        static let errorMessage  = "health.error"
        static let retryButton   = "health.button.retry"
        static let doneButton    = "health.button.done"
        /// The note explaining that compromised-password checking is not performed.
        static let breachNote    = "health.breachNote"

        /// One check's section; `check` is `HealthCheck.rawValue`.
        static func section(_ check: String) -> String { "health.section.\(check)" }
        /// The finding-count badge in a section header.
        static func sectionCount(_ check: String) -> String { "health.section.\(check).count" }
        /// One finding row; `index` is its position within its own section.
        static func findingRow(_ check: String, _ index: Int) -> String {
            "health.finding.\(check).\(index)"
        }
    }
}
