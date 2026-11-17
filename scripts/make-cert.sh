#!/bin/zsh
# Cria o certificado local "Ilha Dev" (autoassinado) no chaveiro de login.
# Com ele o macOS reconhece o app como o mesmo a cada build e a permissão não se perde.
set -e
DIR="$(mktemp -d)"
cd "$DIR"
cat > ilha.cnf <<'C'
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=Ilha Dev
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
C
openssl req -x509 -newkey rsa:2048 -nodes -keyout ilha.key -out ilha.crt -days 3650 -config ilha.cnf
openssl pkcs12 -export -inkey ilha.key -in ilha.crt -out ilha.p12 -passout pass:ilha -legacy
security import ilha.p12 -k ~/Library/Keychains/login.keychain-db -P ilha -T /usr/bin/codesign
rm -rf "$DIR"
echo 'Certificado "Ilha Dev" criado. Rode ./build.sh para assinar com ele.'
