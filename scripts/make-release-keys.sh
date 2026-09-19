#!/bin/sh
# Run once before the first release with self-updating: creates the two
# keys that releases are signed with.
#
#   1. A self-signed certificate "ApolloShell Release Signing" (20 years).
#      The app inside the DMG is signed with it. Why at all: macOS ties the
#      Accessibility grant to the signature. Signed ad-hoc it changes with
#      every build, and the grant would be gone after every update. Same
#      recipe as scripts/setup-signing.sh, except that the certificate is
#      also exported as a .p12 here so CI can use it.
#   2. An EdDSA key pair for Sparkle. The DMG file is signed with it;
#      without a valid signature Sparkle refuses every update. The private
#      key is the 32-byte seed in base64 - exactly what Sparkle's tools
#      read.
#
# The result lands in a folder (default: ~/Downloads/apolloshell-release-keys):
#   release-cert.p12        certificate + private key, password protected
#   release-cert.p12.base64 the same for the GitHub secret
#   release-cert-password   the password
#   sparkle-ed-private.key  private EdDSA key (Sparkle format)
#   sparkle-ed-public.key   public EdDSA key
#
# IMPORTANT: the folder does NOT belong in the repo. Both private keys need
# a backup outside GitHub. If the EdDSA key is lost, no existing install can
# ever update automatically again - rotating it needs a matching Apple
# signature, which we do not have without a Developer ID.
#
# The script writes the public key into Support/Info.plist (SUPublicEDKey).
# That change belongs in a commit.
#
# It distributes nothing: it creates no secrets on GitHub. You do that by
# hand under Settings > Secrets and variables > Actions:
#   RELEASE_CERT_P12       contents of release-cert.p12.base64
#   RELEASE_CERT_PASSWORD  contents of release-cert-password
#   SPARKLE_EDDSA_KEY      contents of sparkle-ed-private.key
#   TAP_DEPLOY_KEY         private SSH key of a deploy key with write access
#                          to homebrew-apolloshell
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$HOME/Downloads/apolloshell-release-keys}
NAME="ApolloShell Release Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# As in setup-signing.sh: macOS' LibreSSL, whose PKCS#12 the keychain
# understands.
OPENSSL=/usr/bin/openssl

mkdir -p "$OUT"
chmod 700 "$OUT"

# --- Certificate ------------------------------------------------------------

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
    echo "certificate already present: $NAME"
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

    # 20 years: if the certificate expires, every user has to grant the
    # permission again.
    "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 7300 \
        -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem"

    PASSWORD=$("$OPENSSL" rand -base64 24)
    printf '%s' "$PASSWORD" > "$OUT/release-cert-password"
    chmod 600 "$OUT/release-cert-password"

    # Force the old PKCS#12 format (see setup-signing.sh).
    "$OPENSSL" pkcs12 -export -out "$OUT/release-cert.p12" \
        -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
        -passout "pass:$PASSWORD"
    chmod 600 "$OUT/release-cert.p12"
    base64 -i "$OUT/release-cert.p12" -o "$OUT/release-cert.p12.base64"

    # Into the login keychain as well, so releases can be built by hand if
    # need be.
    security import "$OUT/release-cert.p12" -k "$KEYCHAIN" -P "$PASSWORD" \
        -T /usr/bin/codesign -T /usr/bin/security
    echo "certificate created: $NAME"
fi

# --- EdDSA key for Sparkle --------------------------------------------------

if [ -s "$OUT/sparkle-ed-private.key" ]; then
    echo "EdDSA key already present: $OUT/sparkle-ed-private.key"
else
    KEYWORK=$(mktemp -d)
    # The private key sits in there unencrypted: remove it under all
    # circumstances, even if something in between fails.
    trap 'rm -rf "${WORK:-}" "$KEYWORK"' EXIT INT TERM
    # Via CryptoKit instead of openssl: macOS' LibreSSL does not know
    # "genpkey -algorithm ed25519". Sparkle expects base64 of 64 bytes -
    # 32 bytes private key, followed by the 32 bytes of the public one.
    cat > "$KEYWORK/edkey.swift" <<'SWIFT'
import CryptoKit
import Foundation

// Sparkle expects exactly the 32-byte seed, base64 (common_cli/Secret.swift:
// 32 bytes = seed, 96 bytes = old format). The error message from
// sign_update talks about "64 bytes or 96 bytes decoded" and means the old
// format of 64 + 32 - 64 bytes on their own are refused.
let key = Curve25519.Signing.PrivateKey()
print(key.rawRepresentation.base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
SWIFT
    swift "$KEYWORK/edkey.swift" > "$KEYWORK/keys.txt"
    head -1 "$KEYWORK/keys.txt" > "$OUT/sparkle-ed-private.key"
    tail -1 "$KEYWORK/keys.txt" > "$OUT/sparkle-ed-public.key"
    rm -rf "$KEYWORK"
    chmod 600 "$OUT/sparkle-ed-private.key"
    echo "EdDSA key created: $OUT/sparkle-ed-private.key"
fi

# --- Write the public key into the bundle -----------------------------------

PUBLIC=$(tr -d '\n' < "$OUT/sparkle-ed-public.key")
# With sed instead of PlistBuddy: PlistBuddy rewrites the whole file, sorts
# the keys around and throws the comments away.
/usr/bin/sed -i '' -e "/<key>SUPublicEDKey<\/key>/{n;s|<string>.*</string>|<string>$PUBLIC</string>|;}" \
    "$ROOT/Support/Info.plist"
plutil -lint "$ROOT/Support/Info.plist" >/dev/null
echo "SUPublicEDKey set in Support/Info.plist (commit it)"

cat <<EOF

Done. Both private keys are in:
  $OUT
Back them up outside GitHub, then create the four secrets (see the head of
this script). The folder itself does not belong in the repo.
EOF
