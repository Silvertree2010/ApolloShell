#!/bin/sh
set -eu

NAME="Launcher Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
    echo "schon vorhanden: $NAME"
    exit 0
fi

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

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem"

P12PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)
export P12PASS
"$OPENSSL" pkcs12 -export -name "$NAME" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout env:P12PASS -out "$WORK/identity.p12"

security import "$WORK/identity.p12" -k "$KEYCHAIN" -f pkcs12 \
    -P "$P12PASS" -T /usr/bin/codesign

security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
    echo "fertig: ./build.sh signiert ab jetzt mit \"$NAME\"."
    echo "Danach Launcher in Datenschutz & Sicherheit > Bedienungshilfen einmal neu freigeben."
else
    echo "Identitaet angelegt, aber nicht als gueltig gelistet - Vertrauen pruefen (Schluesselbundverwaltung)." >&2
    exit 1
fi
