import SwiftUI

// MARK: - ItemDetailView

/// Detail pane: type-specific content, metadata footer, edit sheet.
struct ItemDetailView: View {

    let item:              VaultItem?
    let faviconLoader:     FaviconLoader
    let folders:           [Folder]
    var organizations:     [Organization] = []
    let onCopy:            (String) -> Void
    let makeEditViewModel: (VaultItem) -> ItemEditViewModel
    /// Factory that creates an `AttachmentAddViewModel` for the given cipher ID.
    /// Injected from `AppContainer` so `ItemDetailView` stays decoupled from Data layer.
    var makeAddAttachmentViewModel: ((String) -> AttachmentAddViewModel)? = nil
    /// Factory that creates an `AttachmentBatchViewModel` for a drag-and-drop upload.
    var makeBatchAttachmentViewModel: ((String) -> AttachmentBatchViewModel)? = nil
    /// Factory for `AttachmentRowViewModel` — passed to `AttachmentsSectionView` so each
    /// row gets its own ViewModel instance (Constitution §II decoupling).
    var makeAttachmentRowViewModel: ((String, Attachment) -> AttachmentRowViewModel)? = nil
    /// Factory for `PasswordHistoryViewModel`. Only login items use it, and only ones the server
    /// says carry a history; the detail view decides that, not the container.
    var makePasswordHistoryViewModel: ((String) -> PasswordHistoryViewModel)? = nil
    var makePasskeysViewModel: ((String) -> PasskeysViewModel)? = nil
    /// Factory for `TOTPCodeViewModel`; the second argument is the item's stored authenticator key.
    /// Only login items use it, and only ones that actually carry a key.
    var makeTOTPCodeViewModel: ((String, String?) -> TOTPCodeViewModel)? = nil
    /// Derives a one-time code for the header's Copy code action.
    ///
    /// Injected as the Domain protocol rather than used to build a view model, because the header
    /// needs a code at the instant the button is pressed and nothing else. A held view model would
    /// mean a timer running for a button the user may never press — and a code read from one that has
    /// gone stale is simply the wrong code.
    var totpGenerator: (any TOTPGenerator)? = nil
    /// Called when an attachment upload sheet is dismissed, whether the upload
    /// succeeded or was cancelled. The parent view uses this to refresh `itemSelection`
    /// so the attachment list in the detail pane reflects the new server state.
    var onAttachmentsChanged: (() -> Void)? = nil
    var onEditSheetChanged: ((Bool) -> Void)? = nil
    var onSoftDelete: ((String) async -> Void)? = nil
    var onRestore: ((String) async -> Void)? = nil
    var onPermanentDelete: ((String) async -> Void)? = nil
    /// Favourites or unfavourites the selected item. `VaultBrowserView` routes this to the view model,
    /// which is the only place that knows how to rebuild the draft without losing fields.
    var onToggleFavorite: ((VaultItem) -> Void)? = nil
    var editTrigger: Int = 0
    var saveTrigger: Int = 0

    /// The master-password gate for the selected item's secrets. Built by `VaultBrowserView` from
    /// the view model, which owns the grants and the reveal state.
    var gate: RevealGateBinding = .none

    @State private var isEditSheetPresented = false
    @State private var editViewModel: ItemEditViewModel?

    // Both add-attachment and batch sheets use .sheet(item:) so SwiftUI receives the
    // ViewModel directly — eliminating the race where the sheet body evaluated before
    // the optional ViewModel state was committed, producing a blank sheet window.
    @State private var addAttachmentViewModel: AttachmentAddViewModel?
    @State private var isPickingAttachment = false   // drives spinner while NSOpenPanel blocks

    @State private var batchAttachmentViewModel: AttachmentBatchViewModel?

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if let item {
            ScrollView {
                VStack(spacing: 0) {
                    if item.isDeleted { trashBanner(for: item) }

                    itemHeader(for: item)
                    actionRow(for: item)
                    typeDetailView(for: item)
                    attachmentsSection(for: item)

                    Spacer(minLength: 20)
                    metadataFooter(for: item)
                }
            }
            .sheet(isPresented: $isEditSheetPresented, onDismiss: {
                editViewModel = nil
                onEditSheetChanged?(false)
            }) {
                if let vm = editViewModel {
                    ItemEditView(viewModel: vm, isPresented: $isEditSheetPresented,
                                 onDelete: onSoftDelete)
                }
            }
            .sheet(item: $addAttachmentViewModel, onDismiss: {
                onAttachmentsChanged?()
            }) { vm in
                AttachmentConfirmSheet(viewModel: vm)
            }
            .sheet(item: $batchAttachmentViewModel, onDismiss: {
                onAttachmentsChanged?()
            }) { vm in
                AttachmentBatchSheet(viewModel: vm)
            }
            .onChange(of: editTrigger) { if !item.isDeleted { openEditSheet(for: item) } }
            .onChange(of: saveTrigger) { editViewModel?.save() }
        } else {
            ContentUnavailableView(
                "No Item Selected",
                systemImage: "square.dashed",
                description: Text("Select an item from the list.")
            )
            .accessibilityIdentifier(AccessibilityID.Detail.emptyState)
        }
    }

    // MARK: - Subviews

    /// The item's name, what it is, and where it lives.
    ///
    /// The folder and organisation used to be two cards at the bottom of the scroll, below every
    /// field — the one place a user checks to confirm they are looking at the right account, parked
    /// out of sight. They are in the header now, beside the name, which is where they are read.
    @ViewBuilder
    private func itemHeader(for item: VaultItem) -> some View {
        let type = itemType(for: item)
        HStack(spacing: Spacing.detailRowGap) {
            ZStack {
                RoundedRectangle(cornerRadius: Spacing.detailChipCornerRadius)
                    .fill(type.tint.opacity(Opacity.typeChip(contrast)))
                FaviconView(
                    domain:   primaryDomain(for: item),
                    itemType: type,
                    loader:   faviconLoader,
                    size:     Spacing.detailChipIcon,
                    tint:     type.tint
                )
            }
            .frame(width: Spacing.detailChip, height: Spacing.detailChip)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.isEmpty ? " " : item.name)
                    .font(Typography.detailTitle)
                    .accessibilityIdentifier(AccessibilityID.Detail.itemName)
                Text(breadcrumb(for: item))
                    .font(Typography.breadcrumb)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier(AccessibilityID.Detail.breadcrumb)
            }

            Spacer(minLength: 0)

            // The item's own commands, beside the item they act on.
            //
            // They used to live in the window toolbar, which cost the window its shape: seven
            // equal-weight circles in a row, where favouriting this item looked exactly like opening
            // Settings, and the right end of the titlebar emptied out whenever nothing was selected.
            if !item.isDeleted {
                favoriteToggle(for: item)

                Button(L("Edit")) { openEditSheet(for: item) }
                    .disabled(isEditSheetPresented)
                    .keyboardShortcut("e", modifiers: .command)
                    .accessibilityIdentifier(AccessibilityID.Edit.editButton)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.detailHeaderTop)
        .padding(.horizontal, Spacing.detailMargin)
        .padding(.bottom, Spacing.detailHeaderBottom)
    }

    /// Favourite this item, or stop favouriting it.
    ///
    /// A control, replacing the display-only glyph that was here. The toolbar already had a star that
    /// toggled, so a favourited item showed two stars and only one of them did anything.
    private func favoriteToggle(for item: VaultItem) -> some View {
        Button {
            onToggleFavorite?(item)
        } label: {
            Image(systemName: item.isFavorite ? "star.fill" : "star")
                .foregroundStyle(item.isFavorite ? .yellow : .secondary)
        }
        .buttonStyle(.borderless)
        .help(item.isFavorite ? L("Unfavorite") : L("Favorite"))
        .accessibilityLabel(item.isFavorite ? L("Unfavorite") : L("Favorite"))
        .accessibilityValue(item.isFavorite ? L("Favorited") : L("Not favorited"))
        .accessibilityIdentifier(AccessibilityID.Detail.favoriteToggle)
    }

    /// What places this item: its login name, its folder, its organisation.
    private func breadcrumb(for item: VaultItem) -> String {
        var parts: [String] = []
        if case .login(let login) = item.content,
           let username = login.username, !username.isEmpty {
            parts.append(username)
        }
        if let folderId = item.folderId,
           let folder = folders.first(where: { $0.id == folderId }) {
            parts.append(folder.name)
        }
        if let orgId = item.organizationId,
           let org = organizations.first(where: { $0.id == orgId }) {
            parts.append(org.name)
        }
        // Naming the absence rather than leaving the line blank: an item with no username, no folder
        // and no organisation is a personal one, and that is worth saying.
        return parts.isEmpty ? L("Personal vault") : parts.joined(separator: "  ·  ")
    }

    /// The actions the selected item can actually perform.
    ///
    /// These existed before, but only on hover over an individual row, in the toolbar, or in the Item
    /// menu — three places to look when arriving at an item. A button is rendered only for a value
    /// this item holds, so a secure note gets no action row at all.
    @ViewBuilder
    private func actionRow(for item: VaultItem) -> some View {
        let actions = Self.headerActions(for: item, totpGenerator: totpGenerator)

        if !actions.isEmpty {
            HStack(spacing: Spacing.detailRowGap) {
                ForEach(actions) { action in
                    actionButton(action, for: item)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.detailMargin)
            .padding(.bottom, Spacing.detailActionsBottom)
        }
    }

    @ViewBuilder
    private func actionButton(_ action: DetailAction, for item: VaultItem) -> some View {
        switch action {
        case .copyPassword:
            Button {
                // The value is read again here rather than carried in from the decision that drew the
                // button: an edit can replace the password between one render and the next.
                if let password = passwordValue(of: item) { deliver(password) }
            } label: {
                DetailActionLabel(title: L("Copy password"),
                                  systemImage: "doc.on.doc",
                                  isProminent: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.Detail.copyPasswordButton)

        case .copyCode:
            Button {
                // Derived at the press, not at the render — a code copied from a stale computation is
                // simply the wrong code.
                if let code = codeValue(of: item) { deliver(code) }
            } label: {
                DetailActionLabel(title: L("Copy code"),
                                  systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.Detail.copyCodeButton)

        case .openWebsite(let url):
            Link(destination: url) {
                DetailActionLabel(title: L("Open website"),
                                  systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.Detail.openWebsiteButton)
        }
    }

    // MARK: - Which actions the header offers

    /// One action the detail header can offer for the selected item.
    enum DetailAction: Equatable, Identifiable {
        case copyPassword
        case copyCode
        case openWebsite(URL)

        var id: String {
            switch self {
            case .copyPassword:      return "copyPassword"
            case .copyCode:          return "copyCode"
            case .openWebsite(let u): return "openWebsite:\(u.absoluteString)"
            }
        }
    }

    /// The actions `item` can perform, in the order the header shows them.
    ///
    /// Extracted from the view because "a secure note offers no copy-password button" and "an
    /// authenticator key that yields no code offers no copy-code button" are decisions, not styling,
    /// and a dead button that promises something the item cannot do is the failure being avoided.
    /// Kept `static` and total so those are testable without a window.
    static func headerActions(for item: VaultItem,
                              totpGenerator: (any TOTPGenerator)? = nil) -> [DetailAction] {
        guard case .login(let login) = item.content else { return [] }

        var actions: [DetailAction] = []
        if let password = login.password, !password.isEmpty {
            actions.append(.copyPassword)
        }
        // Only when the stored key actually produces a code. The key is often a malformed or
        // unsupported value, and the row below already says so — a header button beside it that would
        // do nothing is a second, louder claim that something is available.
        if let code = totpGenerator?.code(for: login.totp), !code.isEmpty {
            actions.append(.copyCode)
        }
        if let uri = login.uris.first?.uri, let url = URL(string: uri) {
            actions.append(.openWebsite(url))
        }
        return actions
    }

    private func passwordValue(of item: VaultItem) -> String? {
        guard case .login(let login) = item.content else { return nil }
        return login.password.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The code right now, or nil when the item stores no key or the key yields nothing.
    ///
    /// Derived per render rather than cached. It is one HMAC over a counter, and the alternative —
    /// holding a view model so the button can be shown or hidden — either needs a timer running for a
    /// button that may never be pressed, or risks copying a code that has since rolled over.
    private func codeValue(of item: VaultItem) -> String? {
        guard case .login(let login) = item.content, let totpGenerator else { return nil }
        return totpGenerator.code(for: login.totp)
    }

    /// Puts `value` on the clipboard, through the gate when the item is protected by one.
    ///
    /// The header's buttons are the most convenient copy path on the screen, which makes them exactly
    /// the path a re-prompt gate has to be standing in front of.
    private func deliver(_ value: String) {
        if gate.isGated {
            gate.copyGated?(value)
        } else {
            onCopy(value)
        }
    }

    /// One line: how old the item is, and when it started.
    ///
    /// The two dates used to be a stacked pair in `dd.MM.yyyy`, which answered neither question well.
    /// "Updated" is the one a user is judging — is this stale? — so it is an age; "Created" is a fact
    /// about the item, so it stays a date.
    private func metadataFooter(for item: VaultItem) -> some View {
        Text(L("Updated %@  ·  Created %@",
               Self.updatedLabel(for: item.revisionDate),
               Self.absoluteDateString(item.creationDate)))
            .font(Typography.metaLine)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.detailMargin)
            .padding(.bottom, Spacing.cardBottom)
            .accessibilityIdentifier(AccessibilityID.Detail.metaLine)
    }

    // MARK: - Date formatting

    /// Beyond this many days, the last-modified date stops being shown as an age.
    static let relativeAgeLimitInDays = 30

    /// The last-modified date, as an age while it is recent and as a date once it is not.
    ///
    /// Relative formatting is the better answer while the answer is small — "4 days ago" beats a date
    /// the reader has to subtract from today. Past about a month the formatter produces "last month"
    /// and "1 year ago", which are **vaguer than the date they replaced**, on the one value whose
    /// whole purpose is telling you how stale a credential is. So the line gives up the convenience
    /// when the convenience stops being informative.
    ///
    /// A date in the future — clock skew, a server ahead of the Mac — is shown as a date rather than
    /// turned into "in 3 days", which would be a claim about the future that this view has no basis
    /// for making.
    static func updatedLabel(for date: Date,
                             now: Date = Date(),
                             calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        guard days >= 0, days <= relativeAgeLimitInDays else {
            return absoluteDateString(date, calendar: calendar)
        }
        var style = Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide)
        style.locale = ActiveLocalization.locale
        return date.formatted(style)
    }

    /// An absolute "Mar 12, 2024", following the interface language rather than the system locale.
    static func absoluteDateString(_ date: Date, calendar: Calendar = .current) -> String {
        // Property assignment rather than chaining: `FormatStyle` exposes `calendar` and `locale` as
        // stored vars, so `.calendar(x)` parses as calling the Calendar value as a function.
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        style.calendar = calendar
        style.locale   = ActiveLocalization.locale
        return date.formatted(style)
    }

    @ViewBuilder
    private func trashBanner(for item: VaultItem) -> some View {
        HStack(spacing: Spacing.headerGap) {
            Image(systemName: "trash").foregroundStyle(.secondary)
            Text("This item is in Trash.").font(Typography.bannerText).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.detailMargin)
        .padding(.vertical, Spacing.headerGap)
        .background(Color.secondary.opacity(Opacity.trashBanner(contrast)))
        .accessibilityIdentifier(AccessibilityID.Trash.statusBanner)
    }

    // MARK: - Edit sheet

    private func openEditSheet(for item: VaultItem) {
        guard !isEditSheetPresented else { return }
        editViewModel = makeEditViewModel(item)
        isEditSheetPresented = true
        onEditSheetChanged?(true)
    }

    // MARK: - Helpers

    private func primaryDomain(for item: VaultItem) -> String? {
        guard case .login(let l) = item.content, let first = l.uris.first else { return nil }
        return URL(string: first.uri)?.host
    }

    private func itemType(for item: VaultItem) -> ItemType {
        switch item.content {
        case .login:      .login
        case .card:       .card
        case .identity:   .identity
        case .secureNote: .secureNote
        case .sshKey:     .sshKey
        }
    }

    // MARK: - Attachments section

    @ViewBuilder
    private func attachmentsSection(for item: VaultItem) -> some View {
        AttachmentsSectionView(
            attachments:      item.attachments,
            onAddTapped:      { openAddAttachmentSheet(for: item) },
            onDropFiles:      { urls in openBatchAttachmentSheet(for: item, with: urls) },
            isPicking:        isPickingAttachment,
            makeRowViewModel: makeAttachmentRowViewModel.map { factory in
                { [onAttachmentsChanged] attachment in
                    let vm = factory(item.id, attachment)
                    vm.onAttachmentChanged = onAttachmentsChanged
                    return vm
                }
            }
        )
    }

    private func openAddAttachmentSheet(for item: VaultItem) {
        guard addAttachmentViewModel == nil, !isPickingAttachment,
              let factory = makeAddAttachmentViewModel else { return }
        let vm = factory(item.id)
        // isPickingAttachment drives the spinner independently of the ViewModel reference.
        // addAttachmentViewModel is only set atomically with isAddAttachmentSheetPresented so
        // the sheet body always evaluates with non-nil data on its first render pass —
        // eliminating the blank-sheet flash that occurred when the two writes were separated
        // by the NSOpenPanel session.
        isPickingAttachment = true
        Task {
            await vm.selectFile()
            isPickingAttachment = false
            if vm.isConfirming {
                // Single file — show the per-file confirm sheet.
                addAttachmentViewModel = vm
            } else if !vm.pickedURLs.isEmpty, let batchFactory = makeBatchAttachmentViewModel {
                // Multiple files — route to the batch sheet that already handles N files.
                let batchVM = batchFactory(item.id)
                batchVM.loadItems(from: vm.pickedURLs)
                batchAttachmentViewModel = batchVM
            }
        }
    }

    private func openBatchAttachmentSheet(for item: VaultItem, with urls: [URL]) {
        // Reject new drops while an upload is already in progress (task 6b.4).
        if let existing = batchAttachmentViewModel, existing.isUploading { return }
        guard batchAttachmentViewModel == nil,
              let factory = makeBatchAttachmentViewModel else { return }
        let vm = factory(item.id)
        vm.loadItems(from: urls)
        batchAttachmentViewModel = vm   // non-nil → .sheet(item:) presents immediately
    }

    @ViewBuilder
    private func typeDetailView(for item: VaultItem) -> some View {
        switch item.content {
        case .login(let l):      LoginDetailView(item: item, login: l, onCopy: onCopy,
                                                makePasswordHistoryViewModel: makePasswordHistoryViewModel,
                                                makePasskeysViewModel:        makePasskeysViewModel,
                                                makeTOTPCodeViewModel:        makeTOTPCodeViewModel,
                                                gate: gate)
        case .card(let c):       CardDetailView(item: item, card: c, onCopy: onCopy, gate: gate)
        case .identity(let i):   IdentityDetailView(item: item, identity: i, onCopy: onCopy, gate: gate)
        case .secureNote(let n): SecureNoteDetailView(item: item, secureNote: n, onCopy: onCopy, gate: gate)
        case .sshKey(let k):     SSHKeyDetailView(item: item, sshKey: k, onCopy: onCopy, gate: gate)
        }
    }
}

// MARK: - Detail action label

/// The shared chrome for the detail header's actions, used by both the `Button`s and the `Link`.
///
/// A label view rather than a styled button, because `Link` and `Button` take different styles and
/// the one thing they must agree on is how they look.
private struct DetailActionLabel: View {

    let title:       String
    let systemImage: String
    /// The item's single most likely next action, drawn filled. Exactly one header action is
    /// prominent; more than one and the row stops pointing at anything.
    var isProminent: Bool = false

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: Spacing.badgeHorizontal) {
            Image(systemName: systemImage)
                .font(Typography.chipIcon)
            Text(title)
                .font(Typography.actionButton)
        }
        .foregroundStyle(isProminent ? Color.white : Color.primary)
        .padding(.horizontal, Spacing.actionButtonHorizontal)
        .padding(.vertical, Spacing.actionButtonVertical)
        .background {
            if isProminent {
                RoundedRectangle(cornerRadius: Spacing.actionButtonCornerRadius)
                    .fill(Color.accentColor)
            } else {
                RoundedRectangle(cornerRadius: Spacing.actionButtonCornerRadius)
                    .stroke(Color.primary.opacity(Opacity.hairline(contrast)))
            }
        }
        .contentShape(Rectangle())
    }
}
