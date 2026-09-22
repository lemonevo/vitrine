import SwiftUI

// MARK: - SidebarView

/// Left-column sidebar with sections: Menu Items, Folders, Types, Trash.
///
/// Each row displays a live item count sourced from `VaultBrowserViewModel.itemCounts`.
/// What the sidebar can ask its owner to do.
///
/// Bundled rather than passed as nine separate closures, and the reason is not tidiness: this
/// initializer is called inside `VaultBrowserView`'s body, which the type checker sees as one
/// expression. Adding a single further closure argument to it produced "the compiler is unable to
/// type-check this expression in reasonable time" — pointing, unhelpfully, at an unrelated toolbar
/// button. Bundling removes the class of problem rather than this instance of it.
struct SidebarActions {
    var createFolder: (String) -> Void = { _ in }
    var renameFolder: (String, String) -> Void = { _, _ in }
    var deleteFolder: (Folder) -> Void = { _ in }
    var dropItems: ([String], String) -> Void = { _, _ in }
    var createCollection: (String, String) -> Void = { _, _ in }
    var renameCollection: (String, String, String) -> Void = { _, _, _ in }
    var deleteCollection: (String, String) -> Void = { _, _ in }
    /// Opens the vault-wide verification-codes list.
    var showVerificationCodes: () -> Void = {}
}

/// The sidebar is always visible, even when a category is empty.
struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @State private var sidebarSections: [SidebarSection] = [.menu, .types, .folders, .organizations, .trash]
    let itemCounts: [SidebarSelection: Int]
    let folders: [Folder]
    var organizations: [Organization] = []
    var collections: [OrgCollection] = []

    /// Everything the sidebar can ask its owner to do.
    var actions = SidebarActions()

    // Inline folder rename/create state
    @State private var renamingFolderId: String?
    @State private var renameText: String = ""
    @FocusState private var isRenameFocused: Bool

    @State private var isCreatingFolder = false
    @State private var newFolderName: String = "New Folder"
    @FocusState private var isNewFolderFocused: Bool

    // Inline collection create state: keyed by orgId
    @State private var creatingCollectionInOrg: String? = nil
    @State private var newCollectionName: String = ""
    @FocusState private var isNewCollectionFocused: Bool

    // Inline collection rename state
    @State private var renamingCollectionId: String?
    @State private var renamingCollectionOrgId: String?
    @State private var collectionRenameText: String = ""
    @FocusState private var isCollectionRenameFocused: Bool

    // Delete collection confirmation
    @State private var collectionToDelete: OrgCollection? = nil
    @State private var showDeleteCollectionAlert = false

    // Tree collapse state (per-session)
    @State private var expandedFolderIds: Set<String> = []
    @State private var expandedOrgIds: Set<String> = []

    private var folderTree: [FolderTreeNode] {
        FolderTreeNode.buildTree(from: folders)
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(sidebarSections, id: \.self) { section in
                // Hide the organizations section when the user has no org memberships.
                if section == .organizations && organizations.isEmpty { EmptyView() }
                else {
                    Section(header: sectionHeader(for: section)) {
                        renderRows(for: section)
                    }
                }
            }
            .onMove { from, to in
                sidebarSections.move(fromOffsets: from, toOffset: to)
            }
        }
        .navigationTitle(L("Vitrine"))
        .alert("Delete Collection", isPresented: $showDeleteCollectionAlert,
               presenting: collectionToDelete) { col in
            Button("Delete", role: .destructive) {
                actions.deleteCollection(col.id, col.organizationId)
            }
            Button("Cancel", role: .cancel) {}
        } message: { col in
            Text("\u{201C}\(col.name)\u{201D} will be permanently deleted. Items in this collection will remain in the vault.")
        }
    }

    // MARK: - Section Headers

    @ViewBuilder
    private func sectionHeader(for section: SidebarSection) -> some View {
        switch section {
        case .menu:
            EmptyView()
        case .folders:
            HStack(alignment: .firstTextBaseline) {
                sectionLabel(section.title)
                Spacer()
                Button {
                    newFolderName = "New Folder"
                    isCreatingFolder = true
                    selection = .newFolder
                    isNewFolderFocused = true
                } label: {
                    // `folder.badge.plus`, not `plus.circle`: the symbol is pinned by
                    // `openspec/specs/vault-folder-organization` and described by
                    // `voiceover-labels`. It was changed to `plus.circle` incidentally, inside the
                    // organisation-support PR, which never mentioned it — so it went unnoticed for
                    // months. Do not "tidy" this one.
                    Image(systemName: "folder.badge.plus")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .offset(y: -4)
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                }
                .buttonStyle(.plain)
                .help("New Folder")
                .accessibilityLabel("New Folder")
                .padding(.trailing, 14)
            }
        case .trash:
            EmptyView()
        case .organizations:
            sectionLabel(section.title)
        default:
            sectionLabel(section.title)
        }
    }

    /// A sidebar section heading.
    ///
    /// `Typography.sectionLabel` uppercased and secondary, so the heading reads as a category rather
    /// than as content. At body weight and size it competed with the item rows it introduces — which
    /// is the same objection that removed the letter headings from the item list.
    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Typography.sectionLabel)
            .foregroundStyle(Foreground.muted)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Row Rendering

    @ViewBuilder
    private func renderRows(for section: SidebarSection) -> some View {
        switch section {
        case .menu:
            SidebarRowView(title: SidebarSelection.allItems.displayName, systemImage: "square.grid.2x2", selection: .allItems, count: itemCounts[.allItems] ?? 0, identifier: AccessibilityID.Sidebar.allItems)
            SidebarRowView(title: SidebarSelection.favorites.displayName, systemImage: "star", selection: .favorites, count: itemCounts[.favorites] ?? 0, tint: Foreground.favorite, identifier: AccessibilityID.Sidebar.favorites)

            // A view rather than a scope, so it is a button and carries no selection tag: opening a
            // sheet is not "being in" a category, and a highlighted row left behind afterwards would
            // say otherwise.
            Button(action: actions.showVerificationCodes) {
                Label {
                    Text(L("Verification Codes"))
                        .font(Typography.sidebarRow)
                } icon: {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(Foreground.muted)
                        .frame(width: Spacing.sidebarIconWidth)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.Vault.verificationCodesButton)
        case .folders:
            if isCreatingFolder {
                TextField("Name or Parent/Name", text: $newFolderName, onCommit: {
                    commitCreate()
                })
                .focused($isNewFolderFocused)
                .tag(SidebarSelection.newFolder)
                .help("Nest a folder by adding the parent folder's name followed by a /. Example: Social/Forums")
                .onExitCommand {
                    isCreatingFolder = false
                    selection = nil
                }
            }
            ForEach(folderTree) { node in
                FolderTreeRow(
                    node: node,
                    itemCounts: itemCounts,
                    expandedIds: $expandedFolderIds,
                    renamingFolderId: $renamingFolderId,
                    renameText: $renameText,
                    isRenameFocused: $isRenameFocused,
                    onDeleteFolder: { actions.deleteFolder($0) },
                    onDropItems: { ids, fid in actions.dropItems(ids, fid) },
                    onRenameFolder: { id, name in actions.renameFolder(id, name) }
                )
            }
            if folders.isEmpty && !isCreatingFolder {
                Text("No folders")
                    .font(Typography.listSubtitle)
                    .foregroundStyle(Foreground.muted)
                    .padding(.leading, Spacing.sidebarIconWidth)
                    .tag(SidebarSelection?.none)
            }
        case .types:
            ForEach(ItemType.allCases, id: \.self) { type in
                SidebarRowView(title: type.displayName, systemImage: type.sfSymbol, selection: .type(type), count: itemCounts[.type(type)] ?? 0, tint: type.tint, identifier: AccessibilityID.Sidebar.type(type.rawValue))
            }
        case .organizations:
            ForEach(organizations) { org in
                let orgCollections = collections.filter { $0.organizationId == org.id }
                OrgDisclosureRow(
                    org: org,
                    collections: orgCollections,
                    itemCounts: itemCounts,
                    isExpanded: Binding(
                        get: { expandedOrgIds.contains(org.id) },
                        set: { if $0 { expandedOrgIds.insert(org.id) } else { expandedOrgIds.remove(org.id) } }
                    ),
                    creatingCollectionInOrg: $creatingCollectionInOrg,
                    newCollectionName: $newCollectionName,
                    isNewCollectionFocused: $isNewCollectionFocused,
                    renamingCollectionId: $renamingCollectionId,
                    renamingCollectionOrgId: $renamingCollectionOrgId,
                    collectionRenameText: $collectionRenameText,
                    isCollectionRenameFocused: $isCollectionRenameFocused,
                    onCreateCollection: { name in actions.createCollection(name, org.id) },
                    onRenameCollection: { colId, name in actions.renameCollection(colId, org.id, name) },
                    onDeleteCollection: { col in
                        collectionToDelete = col
                        showDeleteCollectionAlert = true
                    }
                )
            }
        case .trash:
            SidebarRowView(title: SidebarSelection.trash.displayName, systemImage: "trash", selection: .trash, count: itemCounts[.trash] ?? 0, tint: Foreground.muted, identifier: AccessibilityID.Sidebar.trash)
        }
    }

    private func commitCreate() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        isCreatingFolder = false
        selection = nil
        guard !trimmed.isEmpty else { return }
        actions.createFolder(trimmed)
    }
}

// MARK: - FolderTreeRow

/// Recursive tree row: renders a DisclosureGroup for nodes with children,
/// or a plain folder row for leaf nodes.
private struct FolderTreeRow: View {
    let node: FolderTreeNode
    let itemCounts: [SidebarSelection: Int]
    @Binding var expandedIds: Set<String>
    @Binding var renamingFolderId: String?
    @Binding var renameText: String
    @FocusState.Binding var isRenameFocused: Bool
    var onDeleteFolder: (Folder) -> Void
    var onDropItems: ([String], String) -> Void
    var onRenameFolder: ((String, String) -> Void)?

    var body: some View {
        if node.hasChildren {
            DisclosureGroup(isExpanded: Binding(
                get: { expandedIds.contains(node.id) },
                set: { expanded in
                    if expanded { expandedIds.insert(node.id) }
                    else { expandedIds.remove(node.id) }
                }
            )) {
                ForEach(node.children) { child in
                    FolderTreeRow(
                        node: child,
                        itemCounts: itemCounts,
                        expandedIds: $expandedIds,
                        renamingFolderId: $renamingFolderId,
                        renameText: $renameText,
                        isRenameFocused: $isRenameFocused,
                        onDeleteFolder: onDeleteFolder,
                        onDropItems: onDropItems,
                        onRenameFolder: onRenameFolder
                    )
                }
            } label: {
                nodeLabel
            }
        } else {
            nodeLabel
        }
    }

    @ViewBuilder
    private var nodeLabel: some View {
        if let folder = node.folder, renamingFolderId == folder.id {
            TextField("Name or Parent/Name", text: $renameText, onCommit: {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                renamingFolderId = nil
                isRenameFocused = false
                guard !trimmed.isEmpty else { return }
                let parts = folder.name.split(separator: "/").map(String.init)
                let newName = parts.count > 1
                    ? parts.dropLast().joined(separator: "/") + "/" + trimmed
                    : trimmed
                guard newName != folder.name else { return }
                onRenameFolder?(folder.id, newName)
            })
            .focused($isRenameFocused)
            .tag(SidebarSelection.folder(folder.id))
            .help("Nest a folder by adding the parent folder's name followed by a /. Example: Social/Forums")
            .onExitCommand {
                renamingFolderId = nil
                isRenameFocused = false
            }
        } else if let folder = node.folder {
            // Real folder — selectable, droppable
            FolderRowLabel(
                folder: folder,
                displayName: node.name,
                count: itemCounts[.folder(folder.id)] ?? 0,
                onRename: {
                    renameText = node.name
                    renamingFolderId = folder.id
                    isRenameFocused = true
                },
                onDelete: { onDeleteFolder(folder) },
                onDrop: { ids in onDropItems(ids, folder.id) }
            )
        } else {
            // Virtual parent — not selectable, no drop, no context menu
            Label(node.name, systemImage: "folder")
                .foregroundStyle(Foreground.muted)
        }
    }
}

// MARK: - FolderRowLabel

/// Folder row with drop-target highlight and context menu.
/// Extracted to a struct so `@State var isDropTargeted` is per-row.
private struct FolderRowLabel: View {
    let folder: Folder
    var displayName: String? = nil
    let count: Int
    var onRename: () -> Void
    var onDelete: () -> Void
    var onDrop: ([String]) -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isDropTargeted = false

    var body: some View {
        Label {
            Text(displayName ?? folder.name)
                .font(Typography.sidebarRow)
        } icon: {
            Image(systemName: "folder")
                .foregroundStyle(Foreground.muted)
                .frame(width: Spacing.sidebarIconWidth)
        }
            .badge(count)
            .tag(SidebarSelection.folder(folder.id))
            .listRowBackground(isDropTargeted ? Color.accentColor.opacity(Opacity.dropTarget(contrast)) : Color.clear)
            .contextMenu {
                Button("Rename") { onRename() }
                Divider()
                Button("Delete Folder", role: .destructive) { onDelete() }
            }
            .dropDestination(for: String.self) { itemIds, _ in
                guard !itemIds.isEmpty else { return false }
                onDrop(itemIds)
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
    }
}

// MARK: - SidebarSection

enum SidebarSection: String, CaseIterable {
    case menu, folders, types, organizations, trash

    /// Localized section header.
    ///
    /// Deliberately a switch rather than `rawValue.capitalized`: `title` is a
    /// `String`, so `Text(section.title)` uses the *verbatim* initializer and a
    /// capitalized raw value would never be looked up in `Localizable.strings`.
    var title: String {
        switch self {
        case .menu:          return L("Menu")
        case .folders:       return L("Folders")
        case .types:         return L("Types")
        case .organizations: return L("Organizations")
        case .trash:         return L("Trash")
        }
    }
}

// MARK: - OrgDisclosureRow

/// Renders one organization as a DisclosureGroup with its collection rows as children.
/// The header optionally shows a `+` button when the user can manage collections.
private struct OrgDisclosureRow: View {
    let org: Organization
    let collections: [OrgCollection]
    let itemCounts: [SidebarSelection: Int]
    @Binding var isExpanded: Bool

    // Inline collection create state
    @Binding var creatingCollectionInOrg: String?
    @Binding var newCollectionName: String
    @FocusState.Binding var isNewCollectionFocused: Bool

    // Inline collection rename state
    @Binding var renamingCollectionId: String?
    @Binding var renamingCollectionOrgId: String?
    @Binding var collectionRenameText: String
    @FocusState.Binding var isCollectionRenameFocused: Bool

    var onCreateCollection: (String) -> Void
    var onRenameCollection: (String, String) -> Void   // (collectionId, newName)
    var onDeleteCollection: (OrgCollection) -> Void

    private var collectionTree: [CollectionTreeNode] {
        CollectionTreeNode.buildTree(from: collections)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            // Inline new-collection TextField (matching folder create pattern)
            if creatingCollectionInOrg == org.id {
                TextField("Collection name", text: $newCollectionName, onCommit: {
                    commitCreate()
                })
                .focused($isNewCollectionFocused)
                .tag(SidebarSelection.newCollection(organizationId: org.id))
                .onExitCommand {
                    creatingCollectionInOrg = nil
                    newCollectionName = ""
                }
            }

            ForEach(collectionTree) { node in
                CollectionTreeRow(
                    node: node,
                    org: org,
                    itemCounts: itemCounts,
                    renamingCollectionId: $renamingCollectionId,
                    renamingCollectionOrgId: $renamingCollectionOrgId,
                    collectionRenameText: $collectionRenameText,
                    isCollectionRenameFocused: $isCollectionRenameFocused,
                    onRenameCollection: onRenameCollection,
                    onDeleteCollection: onDeleteCollection
                )
            }

            if collections.isEmpty && creatingCollectionInOrg != org.id {
                Text("No collections")
                    .font(Typography.listSubtitle)
                    .foregroundStyle(Foreground.muted)
                    .padding(.leading, Spacing.sidebarIconWidth)
                    .tag(SidebarSelection?.none)
            }
        } label: {
            orgHeader
        }
        .tag(SidebarSelection.organization(org.id))
    }

    @ViewBuilder
    private var orgHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                Text(org.name)
                    .font(Typography.sidebarRow)
            } icon: {
                Image(systemName: "building.2")
                    .foregroundStyle(.indigo)
                    .frame(width: Spacing.sidebarIconWidth)
            }
            Spacer()
            if org.canManageCollections {
                Button {
                    newCollectionName = ""
                    creatingCollectionInOrg = org.id
                    isExpanded = true
                    isNewCollectionFocused = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                }
                .buttonStyle(.plain)
                .help("New Collection")
                .accessibilityLabel("New Collection")
                .padding(.trailing, 2)
                .offset(y: -4)
            }
        }
    }

    private func commitCreate() {
        let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        creatingCollectionInOrg = nil
        newCollectionName = ""
        guard !trimmed.isEmpty else { return }
        onCreateCollection(trimmed)
    }
}

// MARK: - CollectionTreeRow

/// Recursive tree row for collections: renders a DisclosureGroup for nodes with children,
/// or a plain collection row for leaf nodes. Mirrors `FolderTreeRow`.
private struct CollectionTreeRow: View {
    let node: CollectionTreeNode
    let org: Organization
    let itemCounts: [SidebarSelection: Int]
    @Binding var renamingCollectionId: String?
    @Binding var renamingCollectionOrgId: String?
    @Binding var collectionRenameText: String
    @FocusState.Binding var isCollectionRenameFocused: Bool
    var onRenameCollection: (String, String) -> Void   // (collectionId, newName)
    var onDeleteCollection: (OrgCollection) -> Void

    @State private var isExpanded = false

    var body: some View {
        if node.hasChildren {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(node.children) { child in
                    CollectionTreeRow(
                        node: child,
                        org: org,
                        itemCounts: itemCounts,
                        renamingCollectionId: $renamingCollectionId,
                        renamingCollectionOrgId: $renamingCollectionOrgId,
                        collectionRenameText: $collectionRenameText,
                        isCollectionRenameFocused: $isCollectionRenameFocused,
                        onRenameCollection: onRenameCollection,
                        onDeleteCollection: onDeleteCollection
                    )
                }
            } label: {
                nodeLabel
            }
        } else {
            nodeLabel
        }
    }

    @ViewBuilder
    private var nodeLabel: some View {
        if let col = node.collection,
           renamingCollectionId == col.id && renamingCollectionOrgId == col.organizationId {
            TextField("Collection name", text: $collectionRenameText, onCommit: {
                let trimmed = collectionRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
                renamingCollectionId    = nil
                renamingCollectionOrgId = nil
                isCollectionRenameFocused = false
                guard !trimmed.isEmpty, trimmed != col.name else { return }
                onRenameCollection(col.id, trimmed)
            })
            .focused($isCollectionRenameFocused)
            .tag(SidebarSelection.collection(col.id))
            .onExitCommand {
                renamingCollectionId    = nil
                renamingCollectionOrgId = nil
                isCollectionRenameFocused = false
            }
        } else if let col = node.collection {
            Label {
                Text(node.name)
                    .font(Typography.sidebarRow)
            } icon: {
                Image(systemName: "tray.2")
                    .foregroundStyle(Foreground.muted)
                    .frame(width: Spacing.sidebarIconWidth)
            }
                .badge(itemCounts[.collection(col.id)] ?? 0)
                .tag(SidebarSelection.collection(col.id))
                .contextMenu {
                    if org.canManageCollections {
                        Button("Rename") {
                            collectionRenameText    = col.name
                            renamingCollectionId    = col.id
                            renamingCollectionOrgId = col.organizationId
                            isCollectionRenameFocused = true
                        }
                        Divider()
                        Button("Delete Collection", role: .destructive) {
                            onDeleteCollection(col)
                        }
                    }
                }
        } else {
            // Virtual parent node — not selectable, no context menu
            Label(node.name, systemImage: "tray.2")
                .foregroundStyle(Foreground.muted)
        }
    }
}

// MARK: - SidebarRowView

private struct SidebarRowView: View {
    let title:       String
    let systemImage: String
    let selection:   SidebarSelection
    let count:       Int
    /// The icon's colour. Defaults to the accent colour — the menu rows.
    var tint:        Color = .accentColor
    /// The identifier a UI test reaches this row by.
    ///
    /// Required rather than defaulted: `AccessibilityID.Sidebar` declares an identifier for every one
    /// of these rows and none of them was ever applied, so the whole namespace was unreachable. A
    /// default would let the next row be added the same way.
    let identifier:  String

    var body: some View {
        Label {
            Text(title)
                .font(Typography.sidebarRow)
        } icon: {
            // `Label`'s two-argument form styles icon and text together, so the icon is built by hand
            // to carry the type tint while the title stays in the primary text colour.
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: Spacing.sidebarIconWidth)
        }
        .badge(count)
        .tag(selection)
        .accessibilityIdentifier(identifier)
    }
}
