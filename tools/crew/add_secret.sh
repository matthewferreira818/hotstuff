#!/bin/bash
# Add a GitHub Actions secret from Matthew's CLIPBOARD, so no chat ever sees the value
# (Matthew, 2026-11-10: "lets make it so friday can add these keys when prompted").
#
# How it works: Matthew copies the key himself (e.g. in SMTP2GO), then tells Friday "add it as SMTP2GO_API_KEY".
# Friday runs:   tools/crew/add_secret.sh SMTP2GO_API_KEY matthewferreira818/Helm-Private
# The value goes clipboard -> gh -> GitHub. It is never printed, logged, echoed, saved to a file or shown to the chat,
# and the clipboard is wiped afterwards. Friday never reads, types or repeats a secret value (rule 2 still stands).
# Mac only (pbpaste/pbcopy). Needs Matthew's own gh login.
set -euo pipefail
NAME="${1:-}"; REPO="${2:-matthewferreira818/Helm-Private}"
if [[ ! "$NAME" =~ ^[A-Z][A-Z0-9_]{1,63}$ ]]; then
  echo "Usage: add_secret.sh SECRET_NAME [owner/repo]   (name in CAPS, e.g. SMTP2GO_API_KEY)"; exit 2
fi
if [[ "$REPO" != matthewferreira818/* ]]; then echo "Refused: only Matthew's own repos."; exit 2; fi
LEN=$(pbpaste | wc -c | tr -d ' ')
if [ "$LEN" -lt 4 ]; then echo "Clipboard is empty or too short. Matthew: copy the value first, then ask again."; exit 1; fi
if [ "$LEN" -gt 4000 ]; then echo "Clipboard looks too long for a key ($LEN chars). Nothing set."; exit 1; fi
pbpaste | gh secret set "$NAME" --repo "$REPO" >/dev/null
pbcopy </dev/null
echo "Done: $NAME is set on $REPO ($LEN characters; value not shown). Clipboard cleared."
