import Foundation
import XCTest
@testable import Prizm

// MARK: - VaultBrowserViewModelBackupTests

/// Tests for the backup sheet's state machine and the two operations behind it.
///
/// The sheet is one value rather than four booleans precisely so that impossible states cannot be
/// expressed, so most of what is asserted here is *which* state the UI is in after an operation —
/// and, for the failure paths, that no state that looks like success is ever reached.
///
/// The file panels are closures rather than real `NSSavePanel`/`NSOpenPanel` calls, which is what
/// makes all of this testable at all.
@MainActor
final class VaultBrowserViewModelBackupTests: XCTestCase {

    private var vault: MockVaultRepository!
    private var export: MockExportVaultUseCase!
    private var importUseCase: MockImportVaultUseCase!
    private var files: FilePanelRecorder!
    private var sut: VaultBrowserViewModel!

    private let savedURL = URL(fileURLWithPath: "/tmp/prizm_export_test.json")

    // MARK: - Setup

    /// A preference domain private to this test instance.
    ///
    /// Not `.standard`: Xcode runs test classes in parallel *processes*, which share the host app's
    /// preference domain, so clearing a key here deleted it for whichever other suite was running at
    /// the same time. `ItemSortPreferenceTests` already used a per-instance suite; this suite now
    /// does too, and `UserDefaults.standard` is never touched.
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: "\(String(describing: Self.self))-\(UUID().uuidString)")
        defaults.removeObject(forKey: ItemSortPreference.key)
        defaults.removeObject(forKey: ClipboardClearInterval.key)

        vault         = MockVaultRepository()
        export        = MockExportVaultUseCase()
        importUseCase = MockImportVaultUseCase()
        files         = FilePanelRecorder()
        files.saveResult = savedURL

        sut = makeSUT()
    }

    override func tearDown() async throws {
        // The same instance's suite, not a new one — recreating it here would clear a domain nothing
        // had written to. Clearing is belt and braces: the suite is per instance and discarded with it.
        defaults.removeObject(forKey: ItemSortPreference.key)
        defaults.removeObject(forKey: ClipboardClearInterval.key)
        vault = nil
        export = nil
        importUseCase = nil
        files = nil
        sut = nil
        try await super.tearDown()
    }

    private func makeSUT() -> VaultBrowserViewModel {
        let syncRepo = MockSyncTimestampRepository(storedDate: nil)
        return VaultBrowserViewModel(
            vault:            vault,
            search:           BackupStubSearch(),
            delete:           BackupStubDelete(),
            permanentDelete:  BackupStubPermanentDelete(),
            restore:          BackupStubRestore(),
            duplicate:        NoopDuplicateUseCase(),
            emptyTrash:       StubEmptyTrashUseCase(),
            sync:             MockSyncUseCase(),
            createFolder:     BackupStubCreateFolder(),
            renameFolder:     BackupStubRenameFolder(),
            deleteFolder:     BackupStubDeleteFolder(),
            moveItem:         BackupStubMoveItem(),
            createCollection: BackupStubCreateCollection(),
            renameCollection: BackupStubRenameCollection(),
            deleteCollection: BackupStubDeleteCollection(),
            syncTimestamp:    syncRepo,
            getLastSyncDate:  GetLastSyncDateUseCaseImpl(repository: syncRepo),
            export:           export,
            importVault:      importUseCase,
            verifyMasterPassword: VerifyMasterPasswordUseCaseImpl(auth: MockAuthRepository()),
            fileSaver:        files.saver,
            filePicker:       files.picker
        )
    }

    /// The actions run in a detached `Task`, so a test has to wait for the state the UI reads
    /// rather than for the call itself.
    private func waitUntil(timeout: Duration = .seconds(2),
                           _ condition: @escaping () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private var importing: Bool {
        if case .importing = sut.backupSheet { return true }
        return false
    }

    // MARK: - Consent comes first

    /// Nothing is written when the export is requested. The consent is a precondition, not a
    /// confirmation of something already done — Bitwarden's normative security requirements make
    /// it mandatory before any export.
    func test_requestExport_presentsConsentAndWritesNothing() {
        sut.requestExport()

        XCTAssertEqual(sut.backupSheet, .exportConsent)
        XCTAssertEqual(files.saveCallCount, 0, "no file may be written before consent")
        XCTAssertEqual(export.callCount, 0, "the export must not even be built yet")
    }

    /// The consent sheet is dismissed without writing anything.
    func test_dismissFromConsent_writesNothing() {
        sut.requestExport()
        sut.dismissBackupSheet()

        XCTAssertNil(sut.backupSheet)
        XCTAssertEqual(files.saveCallCount, 0)
        XCTAssertNil(sut.actionError)
    }

    /// Two sheets at once is the state the single enum exists to prevent.
    func test_requestExport_isIgnoredWhileASheetIsAlreadyUp() {
        sut.requestExport()
        sut.dismissBackupSheet()

        sut.backupSheet = .importReport(ImportSummary())
        sut.requestExport()

        XCTAssertEqual(sut.backupSheet, .importReport(ImportSummary()),
                       "a second request must not replace an open sheet")
    }

    // MARK: - Export: success

    func test_confirmExport_writesTheFileAndShowsWhereItWent() async {
        sut.requestExport()
        sut.confirmExport()

        await waitUntil { self.sut.backupSheet != .exportConsent }

        XCTAssertEqual(files.saveCallCount, 1)
        XCTAssertEqual(files.savedFilename, "prizm_export_test.json",
                       "the suggested name is what the panel is offered")
        XCTAssertEqual(files.savedData, Data("{}".utf8))
        XCTAssertEqual(sut.backupSheet,
                       .exportDone(url: savedURL, itemCount: 1, organisationItemCount: 0, omittedItemCount: 0))
        XCTAssertNil(sut.actionError)
    }

    /// The counts shown are the export's own, not recomputed from the vault.
    func test_confirmExport_reportsTheOrganisationItemCount() async {
        export.stubbedResult = VaultExport(
            data: Data("{}".utf8), suggestedFilename: "x.json",
            itemCount: 7, organisationItemCount: 3
        )

        sut.requestExport()
        sut.confirmExport()
        await waitUntil { self.sut.backupSheet != .exportConsent }

        XCTAssertEqual(sut.backupSheet,
                       .exportDone(url: savedURL, itemCount: 7, organisationItemCount: 3, omittedItemCount: 0))
    }

    /// Dismissing the done sheet leaves no error behind — the export succeeded.
    func test_dismissFromExportDone_leavesNoError() async {
        sut.requestExport()
        sut.confirmExport()
        await waitUntil { self.sut.backupSheet != .exportConsent }

        sut.dismissBackupSheet()

        XCTAssertNil(sut.backupSheet)
        XCTAssertNil(sut.actionError)
    }

    // MARK: - Export: the user cancelled the panel

    /// A cancelled save panel is a decision, not a failure. The sheet closes and **no** error is
    /// shown, because the user just said no.
    func test_confirmExport_cancelledPanel_closesQuietly() async {
        files.saveResult = nil

        sut.requestExport()
        sut.confirmExport()
        await waitUntil { self.sut.backupSheet == nil }

        XCTAssertEqual(files.saveCallCount, 1, "the panel was shown")
        XCTAssertNil(sut.backupSheet)
        XCTAssertNil(sut.actionError, "cancelling must not raise an error")
    }

    // MARK: - Export: failure

    /// A failed write must surface. A silent failure here would leave the user believing they have
    /// a backup they do not have — which is the worst outcome this feature can produce.
    func test_confirmExport_failedWrite_surfacesAnErrorAndShowsNoSuccess() async {
        struct DiskFull: LocalizedError { var errorDescription: String? { "the disk is full" } }
        files.saveError = DiskFull()

        sut.requestExport()
        sut.confirmExport()
        await waitUntil { self.sut.actionError != nil }

        XCTAssertEqual(sut.actionError, "the disk is full")
        XCTAssertNil(sut.backupSheet, "no done sheet for an export that did not happen")
    }

    /// A failure building the export — an empty vault, say — is surfaced the same way.
    func test_confirmExport_useCaseFailure_surfacesAnError() async {
        export.stubbedError = ExportVaultError.emptyVault

        sut.requestExport()
        sut.confirmExport()
        await waitUntil { self.sut.actionError != nil }

        XCTAssertNotNil(sut.actionError)
        XCTAssertNil(sut.backupSheet)
        XCTAssertEqual(files.saveCallCount, 0, "nothing is offered for saving")
    }

    // MARK: - Import

    /// A cancelled picker leaves no sheet at all. The user said no.
    func test_requestImport_cancelledPicker_leavesNoSheet() {
        files.pickerResult = nil

        sut.requestImport()

        XCTAssertNil(sut.backupSheet)
        XCTAssertNil(sut.actionError)
        XCTAssertEqual(importUseCase.callCount, 0)
    }

    func test_requestImport_success_showsTheReport() async {
        let fileURL = URL(fileURLWithPath: "/tmp/export.json")
        try? Data("{}".utf8).write(to: fileURL)
        files.pickerResult = fileURL

        var summary = ImportSummary()
        summary.imported = 3
        summary.foldersCreated = 1
        importUseCase.stubbedSummary = summary

        sut.requestImport()
        await waitUntil { self.sut.backupSheet == .importReport(summary) }

        XCTAssertEqual(sut.backupSheet, .importReport(summary))
        XCTAssertEqual(importUseCase.callCount, 1)
        XCTAssertNil(sut.actionError)
    }

    /// The bytes handed to the use case are the bytes of the chosen file.
    func test_requestImport_readsTheChosenFile() async {
        let fileURL = URL(fileURLWithPath: "/tmp/export.json")
        let payload = Data(#"{ "encrypted": false, "folders": [], "items": [] }"#.utf8)
        try? payload.write(to: fileURL)
        files.pickerResult = fileURL

        sut.requestImport()
        await waitUntil { self.importUseCase.lastData != nil }

        XCTAssertEqual(importUseCase.lastData, payload)
    }

    /// An unreadable file is an error the user has to see — nothing was imported.
    func test_requestImport_unreadableFile_surfacesAnError() async {
        files.pickerResult = URL(fileURLWithPath: "/tmp/definitely-not-here-\(UUID().uuidString).json")

        sut.requestImport()
        await waitUntil { self.sut.actionError != nil }

        XCTAssertNotNil(sut.actionError)
        XCTAssertNil(sut.backupSheet)
        XCTAssertEqual(importUseCase.callCount, 0)
    }

    /// A refused file — not an unencrypted export — is surfaced, not swallowed.
    func test_requestImport_refusedFile_surfacesAnError() async {
        let fileURL = URL(fileURLWithPath: "/tmp/encrypted.json")
        try? Data(#"{ "encrypted": true }"#.utf8).write(to: fileURL)
        files.pickerResult = fileURL
        importUseCase.stubbedError = VaultExportDocumentError.encryptedExportUnsupported

        sut.requestImport()
        await waitUntil { self.sut.actionError != nil }

        XCTAssertNotNil(sut.actionError)
        XCTAssertNil(sut.backupSheet)
    }

    // MARK: - Progress

    /// The progress sheet is up before the run starts, and it is **indeterminate**: the file has
    /// not been read yet, so the total is not known and a determinate bar would be a lie.
    ///
    /// Asserted synchronously because `requestImport()` sets the state before it starts the task —
    /// so this is the state the view renders on the first frame.
    ///
    /// The per-step values emitted during the run are deliberately not asserted here. They are
    /// delivered through an asynchronous hop (`Task { @MainActor in … }`) and the run finishes
    /// first, so catching an intermediate value would be a race. What *is* asserted is the guard
    /// that matters: a late callback cannot resurrect a dismissed sheet (see the dismissal tests).
    func test_requestImport_entersAnIndeterminateImportingState() async {
        let fileURL = URL(fileURLWithPath: "/tmp/export.json")
        try? Data("{}".utf8).write(to: fileURL)
        files.pickerResult = fileURL

        sut.requestImport()

        XCTAssertEqual(sut.backupSheet, .importing(done: 0, total: 0))
        XCTAssertTrue(importing)

        await waitUntil { self.sut.backupSheet == .importReport(ImportSummary()) }
        XCTAssertFalse(importing, "the run is over, so the sheet is no longer importing")
    }

    // MARK: - Dismissal during a run

    /// Dismissing cancels the run rather than letting it create items behind a closed window.
    func test_dismissDuringImport_clearsTheSheet() async {
        let fileURL = URL(fileURLWithPath: "/tmp/export.json")
        try? Data("{}".utf8).write(to: fileURL)
        files.pickerResult = fileURL

        // Fires inside `execute`, so the dismissal happens while the run is genuinely in flight.
        importUseCase.onExecute = { [weak self] in self?.sut.dismissBackupSheet() }

        sut.requestImport()
        await waitUntil { self.importUseCase.callCount == 1 }
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(sut.backupSheet, "the sheet stays closed")
    }

    /// A cancelled import returns a partial summary rather than throwing, so without a guard the
    /// report would be presented into a sheet the user had just dismissed.
    func test_dismissDuringImport_doesNotRePresentTheReport() async {
        let fileURL = URL(fileURLWithPath: "/tmp/export.json")
        try? Data("{}".utf8).write(to: fileURL)
        files.pickerResult = fileURL

        var summary = ImportSummary()
        summary.imported = 2
        importUseCase.stubbedSummary = summary
        importUseCase.onExecute = { [weak self] in self?.sut.dismissBackupSheet() }

        sut.requestImport()
        await waitUntil { self.importUseCase.callCount == 1 }
        // Long enough for the run to finish and try to assign the report.
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(sut.backupSheet, "dismissing must not bring the sheet back")
    }

    /// Dismissing from the report closes it normally.
    func test_dismissFromReport_clearsTheSheet() async {
        let fileURL = URL(fileURLWithPath: "/tmp/export.json")
        try? Data("{}".utf8).write(to: fileURL)
        files.pickerResult = fileURL

        sut.requestImport()
        await waitUntil { self.sut.backupSheet == .importReport(ImportSummary()) }

        sut.dismissBackupSheet()

        XCTAssertNil(sut.backupSheet)
    }

    // MARK: - The sheet value itself

    func test_isImporting_isTrueOnlyForTheProgressState() {
        XCTAssertTrue(VaultBackupSheet.importing(done: 0, total: 0).isImporting)
        XCTAssertTrue(VaultBackupSheet.importing(done: 4, total: 9).isImporting)
        XCTAssertFalse(VaultBackupSheet.exportConsent.isImporting)
        XCTAssertFalse(VaultBackupSheet.importReport(ImportSummary()).isImporting)
        XCTAssertFalse(
            VaultBackupSheet.exportDone(url: savedURL, itemCount: 1, organisationItemCount: 0, omittedItemCount: 0)
                .isImporting
        )
    }

    /// The states are distinguishable, which is what lets the view switch on them.
    func test_sheetStates_areDistinct() {
        let states: [VaultBackupSheet] = [
            .exportConsent,
            .exportDone(url: savedURL, itemCount: 1, organisationItemCount: 0, omittedItemCount: 0),
            .importing(done: 0, total: 0),
            .importReport(ImportSummary())
        ]
        for (i, lhs) in states.enumerated() {
            for (j, rhs) in states.enumerated() where i != j {
                XCTAssertNotEqual(lhs, rhs)
            }
        }
    }
}

// MARK: - FilePanelRecorder

/// Stands in for the App layer's `NSSavePanel`/`NSOpenPanel` closures.
///
/// `nil` from the saver means "the user cancelled" and a thrown error means "the write failed".
/// Keeping those two apart is the whole reason the seam has this shape, so the recorder models
/// both.
@MainActor
private final class FilePanelRecorder {

    private(set) var saveCallCount = 0
    private(set) var savedFilename: String?
    private(set) var savedData: Data?
    private(set) var pickerCallCount = 0

    /// What the save panel returns. `nil` means the user cancelled.
    var saveResult: URL?
    /// Thrown by the save panel when the write fails.
    var saveError: Error?
    /// What the open panel returns. `nil` means the user cancelled.
    var pickerResult: URL?

    var saver: @MainActor (String, Data) throws -> URL? {
        { [weak self] filename, data in
            guard let self else { return nil }
            self.saveCallCount += 1
            self.savedFilename = filename
            self.savedData = data
            if let error = self.saveError { throw error }
            return self.saveResult
        }
    }

    var picker: @MainActor () -> URL? {
        { [weak self] in
            guard let self else { return nil }
            self.pickerCallCount += 1
            return self.pickerResult
        }
    }
}

// MARK: - No-op dependencies
//
// `private` because several suites declare same-named stubs for the same protocols, and top-level
// `private` is file-scoped in Swift. These exist only so this file can build a browser view model
// without pulling in behaviour it is not testing.

@MainActor private final class BackupStubSearch: SearchVaultUseCase {
    func execute(query: String, in selection: SidebarSelection) throws -> [VaultItem] { [] }
}
@MainActor private final class BackupStubDelete: DeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}
@MainActor private final class BackupStubPermanentDelete: PermanentDeleteVaultItemUseCase {
    func execute(id: String) async throws {}
}
@MainActor private final class BackupStubRestore: RestoreVaultItemUseCase {
    func execute(id: String) async throws {}
}
@MainActor private struct BackupStubCreateFolder: CreateFolderUseCase {
    func execute(name: String) async throws -> Folder { Folder(id: "stub", name: name) }
}
@MainActor private struct BackupStubRenameFolder: RenameFolderUseCase {
    func execute(id: String, name: String) async throws -> Folder { Folder(id: id, name: name) }
}
@MainActor private struct BackupStubDeleteFolder: DeleteFolderUseCase {
    func execute(id: String) async throws {}
}
@MainActor private struct BackupStubMoveItem: MoveItemToFolderUseCase {
    func execute(itemId: String, folderId: String?) async throws {}
    func execute(itemIds: [String], folderId: String?) async throws {}
}
@MainActor private struct BackupStubCreateCollection: CreateCollectionUseCase {
    func execute(name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: "stub", organizationId: organizationId, name: name)
    }
}
@MainActor private struct BackupStubRenameCollection: RenameCollectionUseCase {
    func execute(collectionId: String, name: String, organizationId: String) async throws -> OrgCollection {
        OrgCollection(id: collectionId, organizationId: organizationId, name: name)
    }
}
@MainActor private struct BackupStubDeleteCollection: DeleteCollectionUseCase {
    func execute(collectionId: String, organizationId: String) async throws {}
}
