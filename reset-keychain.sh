#!/bin/zsh
#
# reset-keychain.sh — clear Vitrine's entries from the login keychain.
#
# Why this is needed
# ------------------
# These builds are ad-hoc signed, so macOS grants keychain access per *binary*, not
# per bundle ID. Items written by one build are not necessarily owned by the next,
# and touching them raises:
#
#     "Vitrine" wants to use your confidential information stored in
#     "dev.lemonevo.vitrine" in your keychain. To allow this, enter the "login"
#     keychain password.
#
# That dialog asks for the *login keychain* password — normally the macOS account
# password, and NOT the vault master password. If it is not accepted the prompt
# reappears on every launch and the app never starts.
#
# Deleting the stale items breaks the loop: the app then finds nothing, starts at
# the sign-in screen, and writes fresh items that it owns outright.
#
# Which services
# --------------
# `SERVICES` lists every service name this app has written, because an item left
# under an old name raises exactly the same prompt as one under a current name:
#
#   dev.lemonevo.vitrine   the session store — a single generic-password item whose
#                          account is "store", holding the device id, tokens, email
#                          and KDF parameters.
#   com.prizm.biometric    the Touch ID copy of the vault key.
#   com.prizm              what the session store was called *before* the rename to
#                          Vitrine. Nothing reads it any more; it is pure leftover.
#
# So a healthy keychain shows one "dev.lemonevo.vitrine" item. Finding nine —
# deviceIdentifier, activeUserId and seven per-user keys — means they were written
# by an older build and are now orphaned; this script cleans them up too.
#
# Scope
# -----
# The mechanism works because these builds are unsigned. `KeychainService` probes for
# the data protection keychain, finds it unwritable without the
# `keychain-access-groups` entitlement, and falls back to the legacy login keychain —
# which is the store this script can read. A properly signed build uses the data
# protection keychain instead, where items are scoped by entitlement rather than by
# binary; that build does not raise the prompt this script exists to clear, and this
# script will not see its items either.
#
# Cost: you have to sign in again, and Touch ID has to be enrolled again. The vault
# itself lives on the server, so no vault data is lost — only the cached session
# (device ID, tokens, email, KDF params) and the biometric key are discarded.
#
# Usage:  ./reset-keychain.sh            # list, then ask for confirmation
#         ./reset-keychain.sh --yes      # delete without asking
#         ./reset-keychain.sh --list     # list only, never delete
#
set -euo pipefail

SERVICES=("dev.lemonevo.vitrine" "com.prizm.biometric" "com.prizm")
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# `security dump-keychain` prints one block per item, each block starting with a
# "keychain:" line. The account line precedes the service line inside a block, so
# we must evaluate the whole block at once rather than streaming attribute by
# attribute (doing it line-by-line is off by one item and silently finds nothing).
#
# One dump is taken and every service filters over the same text. An empty dump is
# tolerated: a fresh machine has no login keychain to read, and "nothing to do" is
# the correct answer there rather than an error.
dump="$(security dump-keychain "$KEYCHAIN" 2>/dev/null || true)"

entries=()
for svc in "${SERVICES[@]}"; do
  while IFS= read -r account; do
    [[ -n "$account" ]] && entries+=("$svc|$account")
  done < <(print -r -- "$dump" | awk -v svc="$svc" '
    BEGIN { RS = "keychain:" }
    index($0, "\"svce\"<blob>=\"" svc "\"") == 0 { next }
    {
      if (!match($0, /"acct"<blob>="[^"]*"/)) next
      a = substr($0, RSTART, RLENGTH)
      sub(/^"acct"<blob>="/, "", a)
      sub(/"$/, "", a)
      if (a != "" && a != "<NULL>") print a
    }')
done

if [[ ${#entries[@]} -eq 0 ]]; then
  echo "Nothing to do — no Vitrine items found in the login keychain."
  exit 0
fi

echo "Found ${#entries[@]} Vitrine item(s) in the login keychain:"
for entry in "${entries[@]}"; do
  echo "  • ${entry%%|*} / ${entry#*|}"
done
echo ""

if [[ "${1:-}" == "--list" ]]; then
  exit 0
fi

echo "Deleting these signs you out and forgets the Touch ID enrolment."
echo "Your vault stays on the server."
echo ""

if [[ "${1:-}" != "--yes" ]]; then
  read -r "reply?Delete them now? [y/N] "
  [[ "$reply" == [yY] ]] || { echo "Aborted."; exit 1 }
fi

deleted=0
for entry in "${entries[@]}"; do
  svc="${entry%%|*}"
  account="${entry#*|}"
  if security delete-generic-password -s "$svc" -a "$account" >/dev/null 2>&1; then
    (( deleted++ )) || true
  else
    echo "  ! could not delete: $svc / $account"
  fi
done

echo "Deleted $deleted of ${#entries[@]}."
echo "Now relaunch:  open \"$(cd "$(dirname "$0")" && pwd)/dist/Vitrine.app\""
