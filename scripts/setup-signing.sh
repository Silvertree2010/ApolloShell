#!/bin/sh
# Run once: create the local signing identity "Launcher Local Signing" in
# the login keychain. build.sh signs with it afterwards.
#
# Why: macOS ties the Accessibility grant (Privacy & Security >
# Accessibility) to the app's code signature, more precisely to its
# "designated requirement". Signed ad-hoc (codesign --sign -) that consists
# only of the binary's hash - and that changes with every build. After
# every ./build.sh the old grant no longer matched: the app is still ticked
# in the list, but gets no right, and the window guard quietly stops
# working. With a fixed certificate the requirement reads
# 'identifier "io.github.silvertree2010.apolloshell" and certificate leaf = H"..."'
# and stays the same across rebuilds.
#
# Self-signed is enough: Gatekeeper does not check a locally built app
# without a quarantine attribute, and TCC only compares whether the
# signature meets the same requirement. Recipe as in
# lldb/scripts/macos-setup-codesign.sh, only in the login instead of the
# system keychain (no sudo needed).
#
# Idempotent: if the identity is already there, nothing happens.
# Afterwards, once: ./build.sh, then grant the app Accessibility again (the
# old grant belongs to the ad-hoc signature).
set -eu

NAME="Launcher Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# macOS' own LibreSSL: `security import` understands its PKCS#12. An
# OpenSSL 3 from nix or Homebrew encrypts with AES/PBKDF2 by default, which
# the keychain refuses with "MAC verification failed". The
# -keypbe/-certpbe/-macalg options below force the old format explicitly
# anyway.
OPENSSL=/usr/bin/openssl

# Without -v: an identity that is not (yet) trusted counts as present too.
if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
    echo "already present: $NAME"
    exit 0
fi

# mktemp -d creates the folder readable only by us (0700); the private key
# only sits in it while the script runs.
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

# 10 years: if the certificate expires, the grant would be gone again.
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem"

# A random password only for the transfer file. Depending on the macOS
# version, `security import` refuses empty passwords.
P12PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)
export P12PASS
"$OPENSSL" pkcs12 -export -name "$NAME" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout env:P12PASS -out "$WORK/identity.p12"

# -T: codesign may use the key without asking (narrower than -A, which
# would give every program access). On the first codesign macOS often still
# asks once - answer "Always Allow". Turning that off would need
# `security set-key-partition-list`, and that needs the login password,
# which this script should not know.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -f pkcs12 \
    -P "$P12PASS" -T /usr/bin/codesign

# Trust for code signing only and only for this one certificate, at user
# level (without -d, so no admin, not system-wide). macOS asks once in a
# dialog for the password. Without it `security find-identity -v` lists the
# identity as invalid (CSSMERR_TP_NOT_TRUSTED).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
    echo "done: ./build.sh now signs with \"$NAME\"."
    echo "Then grant ApolloShell Accessibility again under Privacy & Security."
else
    echo "identity created, but not listed as valid - check the trust settings (Keychain Access)." >&2
    exit 1
fi
