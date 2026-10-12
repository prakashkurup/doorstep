#!/bin/bash
# One-time: creates a self-signed "Doorstep Local Signing" identity in the login
# keychain so rebuilt apps keep the same signature (no repeated Keychain prompts).
set -euo pipefail
if security find-certificate -c "Doorstep Local Signing" >/dev/null 2>&1; then
  echo "Already exists"; exit 0
fi
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT; cd "$D"
cat > cfg <<'CFG'
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=Doorstep Local Signing
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CFG
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cfg 2>/dev/null
P=$(/usr/bin/openssl rand -hex 12)
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -out id.p12 -passout pass:"$P" -name "Doorstep Local Signing" 2>/dev/null
security import id.p12 -k ~/Library/Keychains/login.keychain-db -P "$P" -T /usr/bin/codesign
echo "Created Doorstep Local Signing"
