#!/bin/sh
# Einmalig vor dem ersten Release mit Selbstaktualisierung: erzeugt die
# beiden Schluessel, mit denen Releases signiert werden.
#
#   1. Ein selbst signiertes Zertifikat "ApolloShell Release Signing"
#      (20 Jahre). Damit wird die App im DMG signiert. Warum ueberhaupt: macOS
#      bindet die Bedienungshilfen-Freigabe an die Signatur. Ad-hoc signiert
#      aendert sie sich mit jedem Build, und die Freigabe waere nach jedem
#      Update weg. Gleiches Rezept wie scripts/setup-signing.sh, nur wird das
#      Zertifikat hier zusaetzlich als .p12 exportiert, damit CI es benutzen
#      kann.
#   2. Ein EdDSA-Schluesselpaar fuer Sparkle. Damit wird die DMG-Datei
#      signiert; ohne gueltige Signatur lehnt Sparkle jedes Update ab.
#
# Ergebnis in einem Ordner (Vorgabe: ~/Downloads/apolloshell-release-keys):
#   release-cert.p12        Zertifikat + privater Schluessel, passwortgeschuetzt
#   release-cert.p12.base64 dasselbe fuer das GitHub-Secret
#   release-cert-password   das Passwort
#   sparkle-ed-private.key  privater EdDSA-Schluessel (Sparkle-Format)
#   sparkle-ed-public.key   oeffentlicher EdDSA-Schluessel
#
# WICHTIG: Der Ordner gehoert NICHT ins Repo. Beide privaten Schluessel
# brauchen eine Sicherung ausserhalb von GitHub. Geht der EdDSA-Schluessel
# verloren, kann keine bestehende Installation je wieder automatisch
# aktualisiert werden - eine Rotation setzt eine passende Apple-Signatur
# voraus, und die haben wir ohne Developer ID nicht.
#
# Das Skript traegt den oeffentlichen Schluessel in Support/Info.plist ein
# (SUPublicEDKey). Diese Aenderung gehoert committet.
#
# Verteilt nichts: Es legt keine Secrets auf GitHub an. Das machst du von
# Hand unter Settings > Secrets and variables > Actions:
#   RELEASE_CERT_P12       Inhalt von release-cert.p12.base64
#   RELEASE_CERT_PASSWORD  Inhalt von release-cert-password
#   SPARKLE_EDDSA_KEY      Inhalt von sparkle-ed-private.key
#   TAP_TOKEN              Token mit Schreibrecht auf homebrew-apolloshell
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$HOME/Downloads/apolloshell-release-keys}
NAME="ApolloShell Release Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# Wie in setup-signing.sh: das LibreSSL von macOS, dessen PKCS#12 der
# Schluesselbund versteht.
OPENSSL=/usr/bin/openssl

mkdir -p "$OUT"
chmod 700 "$OUT"

# --- Zertifikat -------------------------------------------------------------

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

    # 20 Jahre: Laeuft das Zertifikat ab, muessen alle Nutzer die Freigabe
    # noch einmal erteilen.
    "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 7300 \
        -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem"

    PASSWORD=$("$OPENSSL" rand -base64 24)
    printf '%s' "$PASSWORD" > "$OUT/release-cert-password"
    chmod 600 "$OUT/release-cert-password"

    # Altes PKCS#12-Format erzwingen (siehe setup-signing.sh).
    "$OPENSSL" pkcs12 -export -out "$OUT/release-cert.p12" \
        -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
        -passout "pass:$PASSWORD"
    chmod 600 "$OUT/release-cert.p12"
    base64 -i "$OUT/release-cert.p12" -o "$OUT/release-cert.p12.base64"

    # Auch lokal in den Anmelde-Schluesselbund, damit Releases zur Not von
    # Hand gebaut werden koennen.
    security import "$OUT/release-cert.p12" -k "$KEYCHAIN" -P "$PASSWORD" \
        -T /usr/bin/codesign -T /usr/bin/security
    echo "Zertifikat erzeugt: $NAME"
fi

# --- EdDSA-Schluessel fuer Sparkle -----------------------------------------

if [ -s "$OUT/sparkle-ed-private.key" ]; then
    echo "EdDSA-Schluessel schon vorhanden: $OUT/sparkle-ed-private.key"
else
    KEYWORK=$(mktemp -d)
    # Darin liegt der private Schluessel unverschluesselt: unter allen
    # Umstaenden wieder loeschen, auch wenn etwas dazwischen scheitert.
    trap 'rm -rf "${WORK:-}" "$KEYWORK"' EXIT INT TERM
    # Ueber CryptoKit statt openssl: Das LibreSSL von macOS kennt
    # "genpkey -algorithm ed25519" nicht. Sparkle erwartet base64 aus 64 Byte -
    # 32 Byte privater Schluessel, dahinter die 32 Byte des oeffentlichen.
    cat > "$KEYWORK/edkey.swift" <<'SWIFT'
import CryptoKit
import Foundation

let key = Curve25519.Signing.PrivateKey()
print((key.rawRepresentation + key.publicKey.rawRepresentation).base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
SWIFT
    swift "$KEYWORK/edkey.swift" > "$KEYWORK/keys.txt"
    head -1 "$KEYWORK/keys.txt" > "$OUT/sparkle-ed-private.key"
    tail -1 "$KEYWORK/keys.txt" > "$OUT/sparkle-ed-public.key"
    rm -rf "$KEYWORK"
    chmod 600 "$OUT/sparkle-ed-private.key"
    echo "EdDSA-Schluessel erzeugt: $OUT/sparkle-ed-private.key"
fi

# --- Oeffentlichen Schluessel ins Bundle eintragen --------------------------

PUBLIC=$(tr -d '\n' < "$OUT/sparkle-ed-public.key")
# Mit sed statt PlistBuddy: PlistBuddy schreibt die ganze Datei neu, sortiert
# die Schluessel um und wirft die Kommentare weg.
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
