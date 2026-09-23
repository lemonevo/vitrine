# Audit findings remediation (P0/P1) — Proposal

## Why

A full audit of this repository against its own documentation and against first-party Bitwarden
sources turned up defects that the existing change history does not cover. Three of them are the
kind this project treats as highest priority — they lose data or reach outside the repository — and
a fourth class is documentation that contradicts the code it describes.

The audit also corrected three claims in `FEATURE-GAP-ANALYSIS.md` that had been left as ❓
"do not act until a first-party source is in hand":

| Claim in the gap analysis | What the first-party source says |
|---|---|
| Favourites pinning on desktop is unverified | The sentence continues past where the analysis quoted it: favourites appear at the top "in browser extensions and mobile apps, and in the **Favorites filter** in your web vault and desktop apps". The desktop behaviour is a filter, so not pinning is **aligned**, not a gap |
| Archive on desktop is unverified | `bitwarden/clients`, `apps/desktop/src/vault/app/vault-v3/vault-items/vault-cipher-row.component.ts` has a `archive()` action. It is a **real** gap |
| Item types 6/7/8 may not exist | `libs/common/src/vault/enums/cipher-type.ts` declares `BankAccount: 6`, `DriversLicense: 7`, `Passport: 8`. They exist, and `CipherMapper` throws on them |

Those three are recorded here because the analysis is the document that scopes future work, and
leaving a resolved ❓ in place is how the wrong thing gets built later.

## What Changes

**Data safety (P0)**

- `VaultRepositoryImpl.update` no longer re-sends collection membership. See Design Decision 1 —
  on Vaultwarden the endpoint applies a symmetric difference, so an empty array removes the item
  from every collection, and a membership this client never learned decodes as empty.
- The release workflow no longer pushes a rewritten cask into the upstream author's Homebrew tap.
  See Design Decision 2.

**Correctness of the tools around the app (P0/P1)**

- `reset-keychain.sh` targets the service names the app actually writes, and reports which ones it
  is about to delete.
- `SECURITY.md` stops contradicting the code on four points: CSV export, certificate pinning, the
  clipboard interval, and the vault cache path.
- `README.md` stops claiming the repository is private, and the build-from-source block clones into
  the directory the repository is actually named.

## Non-goals

Recorded so the next reader does not think they were missed. Each needs a decision that is not this
change's to make:

- **Full support for item types 6/7/8.** New entity shapes, editors and mapper cases — a feature,
  not a fix. The audit over-graded this as P0 on the first pass; items that cannot be read are not
  items that were lost.
- **Wiring up or deleting `Prizm/UITests/`.** `fix-test-target-buildability` records this as "a
  separate decision with its own cost — a UI test target needs a signed app and a UI session", and
  deleting 78 tests is not something to do unasked.
- **Splitting `VaultBrowserViewModel` and the other oversized types.** A refactor with no
  user-visible effect, and the sort of unrequested large change this repository has rejected before.

## Capabilities

- `homebrew-cask` (deltas in `specs/homebrew-cask/`) — the capability described a tap this project
  does not own, and the release workflow acted on it
- `org-vault-items` (collection membership is not re-sent on edit)
- `release-infrastructure` (no upstream tap write)
- `project-documentation` (the README and SECURITY claims above)
- `vault-sync-status` (the export/import and cache facts the docs describe)

## Impact

- No user-visible behaviour changes except the removal of a write that could only damage data.
- One network request per organisation-item edit is removed.
- `reset-keychain.sh` deletes more than it used to; its `--list` mode shows exactly what.
- Suite: 1550 passing before, 1552 after (two regression tests added). Verified by running it.
