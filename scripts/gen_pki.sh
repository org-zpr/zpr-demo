#!/bin/bash
set -e

mkdir -p config/authority
cd config/authority

# Create CA key and cert
openssl genrsa -aes256 -out auth-ca.key 4096
openssl req -x509 -new -nodes -key auth-ca.key -sha256 -days 1826 -out auth-ca.crt

# Create ZPR RSA keypair for signing policies
openssl genrsa -out zpr-rsa-key.pem 2048
openssl req -new -key zpr-rsa-key.pem -out zpr.csr

cat > sign.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = DNS:zpr.local
EOF

openssl x509 -req -in zpr.csr -CA auth-ca.crt -CAkey auth-ca.key -CAcreateserial \\
  -out zpr-rsa.crt -days 1825 -sha256 -extfile sign.ext

cd ../..

# Generate NOISE keys and certs with host-based SANs
for dir in $(find config -type f -name "*.toml" -exec dirname {} \\; | sort -u); do
  name=$(basename "$dir")
  keyfile="$dir/${name}-noise.key"
  certfile="$dir/${name}-noise.crt"
  pubfile="$dir/${name}-noise-pub.pem"
  csrfile="$dir/${name}.csr"
  signext="$dir/sign.ext"

  echo "Generating NOISE key and cert for $name..."

  # Generate private and public key
  ./bin/zpr-pki genkey > "$keyfile"
  ./bin/zpr-pki pubkey < "$keyfile" > "$pubfile"

  # Create custom sign.ext with proper SAN
  cat > "$signext" <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = DNS:${name}.zpr
EOF

  # Sign the public key into a cert with SAN
  ./bin/zpr-pki gensignedcert config/authority/auth-ca.crt config/authority/auth-ca.key \\
    /CN=${name}.zpr 365 < "$pubfile" > "$certfile"

done
