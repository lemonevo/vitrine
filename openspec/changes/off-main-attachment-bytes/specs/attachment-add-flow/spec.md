## MODIFIED Requirements

### Requirement: Upload runs on a background task with progress indicator

The encryption and the upload of a file's bytes SHALL execute on a background executor — not merely
inside a `Task`. The previous wording said "on a background `Task`", which an implementation satisfied
while doing the opposite: a `Task` created from main-actor code runs **on** the main actor, so the file
was encrypted on the thread drawing the interface and the spinner it was supposed to animate could not
animate. See `vault-actor-isolation`'s "Bulk attachment work runs off the main actor" for the executor
rule and its limits.

While in progress, the confirmation sheet SHALL show a progress indicator and disable the Confirm
button; the Cancel button SHALL remain enabled. On success, the sheet SHALL dismiss. On failure, the
sheet SHALL remain open with an inline error.

#### Scenario: Progress indicator shown during upload
- **WHEN** the user confirms and upload begins
- **THEN** a progress indicator SHALL be visible and the Confirm button SHALL be disabled; Cancel SHALL remain enabled

#### Scenario: The indicator is the thing the user can still see
- **WHEN** an upload of a large file is in progress
- **THEN** the interface SHALL remain responsive while the file is read and encrypted, not merely display a progress indicator that cannot redraw

#### Scenario: Cancel during upload aborts and clears file data
- **WHEN** the user presses Cancel while upload is in progress
- **THEN** the upload task SHALL be cancelled, the in-memory file data buffer SHALL be zeroed, and the sheet SHALL dismiss immediately
- **AND** the cancellation SHALL take effect at the next boundary the app controls, because a buffer already being encrypted cannot be abandoned mid-computation

#### Scenario: Upload failure shows inline error with Cancel enabled
- **WHEN** the upload fails (network error, server error, premium gate)
- **THEN** the confirmation sheet SHALL remain open with an inline error message and Cancel SHALL be enabled

#### Scenario: Premium gate error shown inline
- **WHEN** the server returns HTTP 402
- **THEN** the error "Attachments require a Bitwarden Premium account." SHALL be shown on the confirmation sheet
