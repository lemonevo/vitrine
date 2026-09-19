#!/bin/zsh
#
# reset-keychain.sh — clear Prizm's stale entries from the login keychain.
#
# Why this is needed
# ------------------
# Prizm.app is ad-hoc signed, so macOS grants keychain access per *binary*, not
# per bundle ID. Items written by one build are not necessarily owned by the
# next, and touching them raises:
#
#     "Prizm" wants to use your confidential information stored in "com.prizm"
#     in your keychain. To allow this, enter the "login" keychain password.
#
# That dialog asks for the *login keychain* password — normally the macOS account
# password, and NOT the Prizm/vault master password. If it is not accepted the
# prompt reappears on every launch and the app never starts.
#
# Deleting the stale items breaks the loop: the app then finds nothing, starts at
# the sign-in screen, and writes fresh items that it owns outright.
#
# Since the "one item, many keys" change, Prizm keeps its whole session in a single
# generic-password item (account "store"), so a healthy keychain shows exactly one
# "com.prizm" entry. Finding nine — deviceIdentifier, activeUserId and seven
# per-user keys — means they were written by an older build and are now orphaned;
# this script cleans them up.
#
# Cost: you have to sign in again. The vault itself lives on the server, so no
# vault data is lost — only the cached session (device ID, tokens, email, KDF
# params) is discarded.
#
# Usage:  ./reset-keychain.sh            # list, then ask for confirmation
#         ./reset-keychain.sh --yes      # delete without asking
#         ./reset-keychain.sh --list     # list only, never delete
#
set -euo pipefail

SERVICE="com.prizm"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# `security dump-keychain` prints one block per item, each block starting with a
# "keychain:" line. The account line precedes the service line inside a block, so
# we must evaluate the whole block at once rather than streaming attribute by
# attribute (doing it line-by-line is off by one item and silently finds nothing).
accounts=()
while IFS= read -r line; do
  [[ -n "$line" ]] && accounts+=("$line")
done < <(security dump-keychain "$KEYCHAIN" 2>/dev/null | awk -v svc="$SERVICE" '
  BEGIN { RS = "keychain:" }
  index($0, "\"svce\"<blob>=\"" svc "\"") == 0 { next }
  {
    if (!match($0, /"acct"<blob>="[^"]*"/)) next
    a = substr($0, RSTART, RLENGTH)
    sub(/^"acct"<blob>="/, "", a)
    sub(/"$/, "", a)
    if (a != "" && a != "<NULL>") print a
  }')

if [[ ${#accounts[@]} -eq 0 ]]; then
  echo "Nothing to do — no \"$SERVICE\" items found in the login keychain."
  exit 0
fi

echo "Found ${#accounts[@]} \"$SERVICE\" item(s) in the login keychain:"
for a in "${accounts[@]}"; do
  echo "  • $a"
done
echo ""

if [[ "${1:-}" == "--list" ]]; then
  exit 0
fi

echo "Deleting these signs Prizm out. Your vault stays on the server."
echo ""

if [[ "${1:-}" != "--yes" ]]; then
  read -r "reply?Delete them now? [y/N] "
  [[ "$reply" == [yY] ]] || { echo "Aborted."; exit 1 }
fi

deleted=0
for a in "${accounts[@]}"; do
  if security delete-generic-password -s "$SERVICE" -a "$a" >/dev/null 2>&1; then
    (( deleted++ )) || true
  else
    echo "  ! could not delete: $a"
  fi
done

echo "Deleted $deleted of ${#accounts[@]}."
echo "Now relaunch:  open \"$(cd "$(dirname "$0")" && pwd)/dist/Prizm.app\""
