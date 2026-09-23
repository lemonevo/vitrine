# global-search — delta

## ADDED Requirements

### Requirement: The item list shows the results of the query the field holds

Search passes overlap: each keystroke starts one, and they finish in whatever order the vault store
reaches them. A pass SHALL know whether it is still the current one before it writes, so the list
never ends up holding the results of a query the field no longer contains.

#### Scenario: An earlier pass finishes after a later one

- **WHEN** several queries are typed in quick succession, and an earlier pass returns after a newer one
  has already drawn the list
- **THEN** the earlier pass writes nothing, and the list holds the results of the query in the field

#### Scenario: An overtaken pass fails

- **WHEN** a pass is overtaken by a newer query and then its vault read throws
- **THEN** the list keeps what the newer pass drew rather than being cleared by the old failure

#### Scenario: A query typed on its own still lands

- **WHEN** one query is typed and its pass is allowed to finish
- **THEN** the list is replaced with that pass's results — the guard discards overtaken passes, not the
  current one
