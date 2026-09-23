import Combine
import Foundation
import os.log
import SwiftUI

// MARK: - ItemEditViewModel

/// ViewModel for the item edit sheet. Owns the mutable `DraftVaultItem`, orchestrates
/// the async save call, and coordinates discard confirmation and vault-lock dismissal.
///
/// Lifecycle:
/// 1. Created with an existing `VaultItem` when the edit sheet opens.
/// 2. The view binds to `draft` — changes are reflected immediately in the form.
/// 3. `save()` is called when the user presses Save / ⌘S.
/// 4. On success: `isDismissed` is set to `true`; the caller dismisses the sheet.
/// 5. On dismiss (save or discard): the caller should call `clearDraft()` so plaintext does not
///    outlive the sheet.
/// 6. On vault lock: `isDismissed` is set immediately without confirmation.
@MainActor
final class ItemEditViewModel: ObservableObject {

    // MARK: - Published state

    /// The mutable draft being edited. Bound directly to form fields.
    @Published var draft: DraftVaultItem

    /// `true` while the save request is in-flight. Used to disable Save / ⌘S and
    /// change the Save button label to "Saving…".
    @Published private(set) var isSaving: Bool = false

    /// Non-nil when the save request failed. Shown as an inline error banner.
    @Published private(set) var saveError: String? = nil

    /// Set to `true` to signal the enclosing sheet to dismiss.
    @Published private(set) var isDismissed: Bool = false

    // MARK: - Derived state

    /// `true` when the Name field is non-empty, no custom field has a blank name, and no save is
    /// in-flight.
    var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            && draft.unnamedCustomFields.isEmpty
            && !isSaving
    }

    /// Non-nil when `draft.name` is blank, triggering inline validation.
    var nameValidationError: String? {
        draft.name.trimmingCharacters(in: .whitespaces).isEmpty ? L("Name is required") : nil
    }

    /// Non-nil when a custom field has no name.
    ///
    /// The wire format requires a field name and `CipherMapper` skips unnamed fields, so saving
    /// would silently discard the row — leaving the user with a field that appeared to save and did
    /// not. Blocking the save and saying why is the honest alternative.
    var customFieldValidationError: String? {
        draft.unnamedCustomFields.isEmpty ? nil : L("Every custom field needs a name.")
    }

    /// Non-nil when any validation rule fails. Shown in the edit sheet.
    var validationError: String? {
        nameValidationError ?? customFieldValidationError
    }

    /// `true` when any field differs from the original item captured at open time.
    /// Used to decide whether the discard confirmation prompt is needed.
    var hasChanges: Bool {
        draft != original
    }

    /// `true` when editing an existing item (as opposed to creating a new one).
    /// Used to conditionally show the Delete button in the edit sheet.
    var isEditing: Bool { editUseCase != nil }

    /// The strength estimate for the login password, or `nil` when the item is not a login or the
    /// field is empty.
    ///
    /// Computed rather than stored: `draft` is `@Published`, so every keystroke already re-renders
    /// the form and this is re-read on the way past. A stored copy would be one more thing that can
    /// fall out of step with the field it describes.
    var passwordStrength: StrengthEstimate? {
        guard case .login(let content) = draft.content,
              let password = content.password,
              !password.isEmpty else { return nil }
        return strengthEstimator.estimate(password)
    }

    /// Whether the TOTP seed the form currently holds will produce a code, or `nil` when the
    /// field is empty — there is nothing to report about an absent seed.
    ///
    /// The generator is asked rather than a format check written here, because "will this produce
    /// a code" is the question the user will be asking later, when the item silently shows none.
    ///
    /// A seed that does not parse is **not** rejected. Bitwarden stores whatever is pasted and
    /// refusing to save would strand anyone whose service hands out an unusual shape. It is
    /// surfaced instead of swallowed, which is the difference the edit form can actually make.
    var totpSeedProducesCode: Bool? {
        guard case .login(let content) = draft.content,
              let seed = content.totp,
              !seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return totpGenerator.code(for: seed, at: Date()) != nil
    }

    /// The master-password re-prompt setting, as a Bool for the edit form's toggle.
    ///
    /// The domain model and the wire carry an `Int` (0 or 1) because that is what the server
    /// sends and accepts. A toggle has no use for the difference between 0 and "any other
    /// number", so the conversion is made here and nowhere else — a Bool on `DraftVaultItem`
    /// would put a second, differently-typed copy of the setting in the tree.
    var repromptEnabled: Bool {
        get { draft.reprompt != 0 }
        set { draft.reprompt = newValue ? 1 : 0 }
    }

    // MARK: - Private state

    /// Snapshot of the item as it was when the sheet opened — used for `hasChanges`.
    /// `var` so `clearDraft()` can overwrite it with a blank sentinel.
    private var original: DraftVaultItem

    private let editUseCase: (any EditVaultItemUseCase)?
    private let createUseCase: (any CreateVaultItemUseCase)?
    private let strengthEstimator: PasswordStrengthEstimator
    private let totpGenerator: any TOTPGenerator
    private let logger  = Logger(subsystem: "dev.lemonevo.vitrine", category: "ItemEditViewModel")

    /// Called on save success with the server-confirmed `VaultItem` so the caller
    /// (VaultBrowserViewModel or parent) can refresh the list pane.
    var onSaveSuccess: ((VaultItem) -> Void)?

    /// Available folders for the folder picker in the edit sheet.
    let folders: [Folder]

    /// Available organizations — used to resolve collection org names.
    let organizations: [Organization]

    /// Collections available for the collection picker (all orgs).
    let collections: [OrgCollection]

    /// Retain token for the vault-lock observer.
    private nonisolated(unsafe) var lockObserver: NSObjectProtocol?

    // MARK: - Init

    /// Edit mode: initialised with an existing item.
    init(item: VaultItem, useCase: any EditVaultItemUseCase, folders: [Folder] = [],
         organizations: [Organization] = [], collections: [OrgCollection] = [],
         strengthEstimator: PasswordStrengthEstimator = .application,
         totpGenerator: any TOTPGenerator = TOTPGeneratorImpl()) {
        self.draft         = DraftVaultItem(item)
        self.original      = DraftVaultItem(item)
        self.editUseCase   = useCase
        self.createUseCase = nil
        self.folders       = folders
        self.organizations = organizations
        self.collections   = collections
        self.strengthEstimator = strengthEstimator
        self.totpGenerator      = totpGenerator
        subscribeToVaultLock()
    }

    /// Create mode: initialised with a blank draft for the given type.
    init(type: ItemType, useCase: any CreateVaultItemUseCase, folders: [Folder] = [],
         folderId: String? = nil, organizationId: String? = nil, collectionIds: [String] = [],
         organizations: [Organization] = [], collections: [OrgCollection] = [],
         strengthEstimator: PasswordStrengthEstimator = .application,
         totpGenerator: any TOTPGenerator = TOTPGeneratorImpl()) {
        var blank = DraftVaultItem.blank(type: type)
        blank.folderId       = folderId
        blank.organizationId = organizationId
        blank.collectionIds  = collectionIds
        self.draft         = blank
        self.original      = blank
        self.editUseCase   = nil
        self.createUseCase = useCase
        self.folders       = folders
        self.organizations = organizations
        self.collections   = collections
        self.strengthEstimator = strengthEstimator
        self.totpGenerator      = totpGenerator
        subscribeToVaultLock()
    }

    // MARK: - Save

    /// Validates, calls the use case, handles success/failure.
    func save() {
        guard canSave else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            isSaving  = true
            saveError = nil
            do {
                let saved: VaultItem
                if let createUseCase {
                    saved = try await createUseCase.execute(draft: draft)
                } else if let editUseCase {
                    saved = try await editUseCase.execute(draft: draft)
                } else {
                    preconditionFailure("ItemEditViewModel: no use case configured")
                }
                onSaveSuccess?(saved)
                clearDraft()
                isDismissed = true
                logger.info("Item saved: \(self.draft.id, privacy: .public)")
            } catch {
                saveError = error.localizedDescription
                logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
            }
            isSaving = false
        }
    }

    // MARK: - Discard

    /// Discards changes and signals the sheet to dismiss. Call only after confirming
    /// with the user when `hasChanges == true`.
    func discard() {
        clearDraft()
        isDismissed = true
    }

    // MARK: - Memory cleanup

    /// Clears the draft's plaintext field values from memory.
    ///
    /// Called on both the save path (after receiving the server response) and the discard
    /// path. Reduces the window during which plaintext passwords and other secrets are
    /// held in the heap. Swift ARC may retain additional copies; this removes the primary
    /// reference held by this ViewModel.
    func clearDraft() {
        // Replace both draft and original with a blank sentinel to release all
        // string values (passwords, keys, notes) from the heap.
        // `original` must also be cleared — it holds a full snapshot of the item
        // as it was when the sheet opened, including any sensitive plaintext fields.
        let blank = DraftVaultItem(VaultItem(
            id: original.id,
            name: "",
            isFavorite: false,
            isDeleted: false,
            creationDate: original.creationDate,
            revisionDate: original.revisionDate,
            content: .secureNote(SecureNoteContent(notes: nil, customFields: []))
        ))
        draft    = blank
        original = blank
    }

    // MARK: - Vault lock observation

    private func subscribeToVaultLock() {
        lockObserver = NotificationCenter.default.addObserver(
            forName: .vaultDidLock,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Dismiss immediately — no confirmation prompt (spec §8.10).
                self?.clearDraft()
                self?.isDismissed = true
            }
        }
    }

    deinit {
        if let obs = lockObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}
