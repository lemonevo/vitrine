## ADDED Requirements

### Requirement: Cache patches preserve organizationId and collectionIds

Operations that patch a cached `VaultItem` in place — folder deletion, single and bulk move to
folder, soft delete, restore, attachment refresh — SHALL preserve `organizationId` and
`collectionIds`. These operations change one or two fields; they SHALL NOT reconstruct the item
through a memberwise initialiser that omits the rest.

Losing `organizationId` locally is not cosmetic: a subsequent save would encrypt the cipher with the
personal vault key and send `organizationId = null`, converting an org item into a personal one on
the server.

#### Scenario: Deleting a folder keeps org membership
- **GIVEN** an org item that is assigned to a personal folder
- **WHEN** that folder is deleted
- **THEN** the cached item's `organizationId` and `collectionIds` SHALL be unchanged
- **AND** its `folderId` SHALL be nil

#### Scenario: Moving an item keeps org membership
- **GIVEN** an org item is selected
- **WHEN** the item is moved to a folder
- **THEN** the cached item's `organizationId` and `collectionIds` SHALL be unchanged

#### Scenario: Bulk move keeps org membership
- **GIVEN** a mix of personal and org items is moved to a folder
- **WHEN** the bulk move completes
- **THEN** every moved org item SHALL retain its `organizationId` and `collectionIds`

#### Scenario: Soft delete and restore keep org membership
- **GIVEN** an org item
- **WHEN** it is moved to Trash and later restored
- **THEN** `organizationId` and `collectionIds` SHALL be unchanged after both operations

#### Scenario: A field not mentioned by the operation is never cleared
- **WHEN** any cache-patch operation runs
- **THEN** every `VaultItem` field the operation does not explicitly set SHALL keep its previous value
