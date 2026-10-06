#!/bin/zsh
# Double-click this file in Finder: it gets the latest Game Companion from GitHub and rebuilds the app.
# (Friday can't do this for you: rebuilding closes the app, and her hands are not allowed in Terminal on purpose.)
cd "${0:A:h}" || exit 1
echo "Getting the latest version…"
if ! git pull; then
 echo ""
 echo "Couldn't get the latest version (see the message above). Nothing was changed."
 read -k 1 "?Press any key to close this window."
 exit 1
fi
zsh ./rebuild.sh
echo ""
read -k 1 "?All done. Press any key to close this window."
