## MODIFIED Requirements

### Requirement: The window provides new item creation via a toolbar button

The `+` button SHALL be a `ToolbarItem(placement: .primaryAction)` carrying
`AccessibilityID.Create.newItemButton`, opening a `Menu` listing all `ItemType` cases. Selecting a type
opens the create sheet for that type.

It SHALL be drawn at the window's trailing edge rather than inside a column's span, which is where the
reference draws it and where it has to be declared to get there. Declared on a column a toolbar item is
drawn inside that column's span and `placement` has no effect at all — measured in a window-sized probe
of the three-column split, where the same items landed at the leading edge of the content column whether
they were `.automatic` or `.primaryAction`, and at the leading edge again when declared on the split view
itself. Reaching the trailing edge takes `ToolbarSpacer(.flexible)` ahead of the items, declared on the
last column (`VaultBrowserView.detailColumn`, which is where the browser's controls now live).

The button SHALL be conditionally rendered (not merely hidden) when `Trash` is selected — it must be
absent from the view tree so that the ⌘N keyboard shortcut is also disabled in Trash. This was the
requirement's own wording from the start and the code did not honour it: the item was declared beside the
content column unconditionally, so ⌘N stayed live in Trash. It is now built through
`browserToolbarItems`, which omits it when `sidebarSelection == .trash`.

#### Scenario: The create menu sits at the window's trailing edge

- **WHEN** the vault browser is showing, at any window width
- **THEN** `+ New Item` SHALL sit at the trailing edge, after the sort control

#### Scenario: Plus button opens type menu
- **WHEN** the user clicks [+] 
- **THEN** a menu appears listing all item types (Login, Card, Identity, Secure Note, SSH Key)

#### Scenario: ⌘N creates Login outside Trash
- **WHEN** the user presses ⌘N while a non-Trash category is selected
- **THEN** the create sheet opens for a new Login item

#### Scenario: Plus button absent in Trash
- **WHEN** the user selects "Trash" in the sidebar
- **THEN** no [+] button is present and ⌘N has no effect
