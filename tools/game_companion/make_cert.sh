#!/bin/zsh
# One time: makes the self-signed "GameCompanion Signing" certificate that rebuild.sh signs with,
# so macOS keeps Game Companion's permissions across rebuilds. Newer macOS replaced Keychain Access
# with the Passwords app, which can't make certificates, so this does it from Terminal instead.
set -e
NAME="GameCompanion Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then echo "Already have \"$NAME\". Nothing to do."; exit 0; fi
WORK=$(mktemp -d)
cd "$WORK"
cat > cert.cnf <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
# Apple's own openssl (LibreSSL) writes a .p12 that the security tool can import.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout cert.key -out cert.crt -days 3650 -config cert.cnf 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey cert.key -in cert.crt -out cert.p12 -passout pass:temp -name "$NAME"
security import cert.p12 -k ~/Library/Keychains/login.keychain-db -P temp -T /usr/bin/codesign
cd / && rm -rf "$WORK"
echo "Made \"$NAME\". Now run rebuild.sh. If macOS asks to let codesign use the key, enter your Mac password there and choose Always Allow."
