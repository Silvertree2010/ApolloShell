#!/bin/sh
# Einmalig: eigene Signier-Identitaet "Launcher Local Signing" im
# Anmelde-Schluesselbund anlegen. build.sh signiert danach damit.
#
# Warum: macOS bindet die Bedienungshilfen-Freigabe (Datenschutz & Sicherheit
# > Bedienungshilfen) an die Code-Signatur der App, genauer an deren
# "designated requirement". Ad-hoc signiert (codesign --sign -) besteht die
# nur aus dem Hash des Binarys - und der aendert sich mit jedem Build. Nach
# jedem ./build.sh passte die alte Freigabe also nicht mehr: Launcher steht
# zwar noch angehakt in der Liste, bekommt aber kein Recht, und die
# Fensterwache setzt still aus. Mit einem festen Zertifikat lautet die
# Anforderung 'identifier "io.github.silvertree2010.apolloshell" and certificate leaf = H"..."'
# und bleibt ueber Neubauten gleich.
#
# Selbst signiert genuegt: Gatekeeper prueft eine lokal gebaute App ohne
# Quarantaene-Attribut nicht, und TCC vergleicht nur, ob die Signatur
# dieselbe Anforderung erfuellt. Rezept wie lldb/scripts/macos-setup-codesign.sh,
# nur im Anmelde- statt im System-Schluesselbund (kein sudo noetig).
#
# Idempotent: ist die Identitaet schon da, passiert nichts.
# Danach einmal: ./build.sh, dann Launcher in den Bedienungshilfen neu
# freigeben (die alte Freigabe gehoert zur ad-hoc-Signatur).
set -eu

NAME="Launcher Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# macOS-eigenes LibreSSL: dessen PKCS#12 versteht `security import`. Ein
# OpenSSL 3 aus nix oder Homebrew verschluesselt standardmaessig mit
# AES/PBKDF2, das der Schluesselbund mit "MAC verification failed" ablehnt.
# Die -keypbe/-certpbe/-macalg-Angaben unten erzwingen das alte Format
# trotzdem ausdruecklich.
OPENSSL=/usr/bin/openssl

# Ohne -v: auch eine (noch) nicht vertraute Identitaet zaehlt als vorhanden.
if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
    echo "schon vorhanden: $NAME"
    exit 0
fi

# mktemp -d legt den Ordner nur fuer uns lesbar an (0700); der private
# Schluessel liegt nur waehrend des Skripts darin.
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

# 10 Jahre: laeuft das Zertifikat ab, waere die Freigabe wieder weg.
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem"

# Zufaelliges Passwort nur fuer die Uebergabedatei. Leere Passwoerter
# lehnt `security import` je nach macOS-Version ab.
P12PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)
export P12PASS
"$OPENSSL" pkcs12 -export -name "$NAME" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout env:P12PASS -out "$WORK/identity.p12"

# -T: codesign darf den Schluessel ohne Nachfrage benutzen (enger als -A,
# das jedem Programm Zugriff gaebe). Beim ersten codesign fragt macOS
# trotzdem oft einmal nach - dann "Immer erlauben". Abstellen liesse sich
# das nur mit `security set-key-partition-list`, und das braucht das
# Anmeldepasswort, das dieses Skript nicht kennen soll.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -f pkcs12 \
    -P "$P12PASS" -T /usr/bin/codesign

# Vertrauen nur fuer Codesignatur und nur fuer dieses eine Zertifikat, auf
# Benutzerebene (ohne -d, also kein Admin, nicht systemweit). macOS fragt
# dafuer einmal im Dialog nach dem Passwort. Ohne das fuehrt
# `security find-identity -v` die Identitaet als ungueltig
# (CSSMERR_TP_NOT_TRUSTED).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
    echo "fertig: ./build.sh signiert ab jetzt mit \"$NAME\"."
    echo "Danach Launcher in Datenschutz & Sicherheit > Bedienungshilfen einmal neu freigeben."
else
    echo "Identitaet angelegt, aber nicht als gueltig gelistet - Vertrauen pruefen (Schluesselbundverwaltung)." >&2
    exit 1
fi
