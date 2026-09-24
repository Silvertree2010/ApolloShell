#!/bin/sh
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$HOME/Downloads/apolloshell-release-keys}
NAME="ApolloShell Release Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl

mkdir -p "$OUT"
chmod 700 "$OUT"

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
    echo "Zertifikat schon vorhanden: $NAME"
else
    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT INT TERM

    cat > "$WORK/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = codesign
[ dn ]
CN = $NAME
[ codesign ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

    "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 7300 \
        -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem"

    PASSWORD=$("$OPENSSL" rand -base64 24)
    printf '%s' "$PASSWORD" > "$OUT/release-cert-password"
    chmod 600 "$OUT/release-cert-password"

    "$OPENSSL" pkcs12 -export -out "$OUT/release-cert.p12" \
        -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
        -passout "pass:$PASSWORD"
    chmod 600 "$OUT/release-cert.p12"
    base64 -i "$OUT/release-cert.p12" -o "$OUT/release-cert.p12.base64"

    security import "$OUT/release-cert.p12" -k "$KEYCHAIN" -P "$PASSWORD" \
        -T /usr/bin/codesign -T /usr/bin/security
    echo "Zertifikat erzeugt: $NAME"
fi

if [ -s "$OUT/sparkle-ed-private.key" ]; then
    echo "EdDSA-Schluessel schon vorhanden: $OUT/sparkle-ed-private.key"
else
    KEYWORK=$(mktemp -d)
    trap 'rm -rf "${WORK:-}" "$KEYWORK"' EXIT INT TERM
    cat > "$KEYWORK/edkey.swift" <<'SWIFT'
import CryptoKit
import Foundation

let key = Curve25519.Signing.PrivateKey()
print(key.rawRepresentation.base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
SWIFT
    swift "$KEYWORK/edkey.swift" > "$KEYWORK/keys.txt"
    head -1 "$KEYWORK/keys.txt" > "$OUT/sparkle-ed-private.key"
    tail -1 "$KEYWORK/keys.txt" > "$OUT/sparkle-ed-public.key"
    rm -rf "$KEYWORK"
    chmod 600 "$OUT/sparkle-ed-private.key"
    echo "EdDSA-Schluessel erzeugt: $OUT/sparkle-ed-private.key"
fi

PUBLIC=$(tr -d '\n' < "$OUT/sparkle-ed-public.key")
/usr/bin/sed -i '' -e "/<key>SUPublicEDKey<\/key>/{n;s|<string>.*</string>|<string>$PUBLIC</string>|;}" \
    "$ROOT/Support/Info.plist"
plutil -lint "$ROOT/Support/Info.plist" >/dev/null
echo "SUPublicEDKey in Support/Info.plist gesetzt (committen)"

cat <<EOF

Fertig. Beide privaten Schluessel liegen in:
  $OUT
Sichere sie ausserhalb von GitHub, und lege danach die vier Secrets an
(siehe Kopf dieses Skripts). Der Ordner selbst gehoert nicht ins Repo.
EOF
