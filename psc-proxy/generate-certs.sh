#!/bin/bash
set -e

CERTS_DIR="./certs"
CA_DIR="$CERTS_DIR/ca"
CLIENT_DIR="$CERTS_DIR/client"

# Create directory structure
mkdir -p "$CA_DIR"
mkdir -p "$CLIENT_DIR"

echo "Generating certificates for pol-kc (Keycloak) and polari-proxy..."

# 1. Generate CA private key and certificate
echo "1. Generating CA certificate..."
openssl genrsa -out "$CA_DIR/pol-kc.key" 4096
openssl req -new -x509 -days 3650 -key "$CA_DIR/pol-kc.key" -out "$CA_DIR/pol-kc.crt" \
    -subj "/C=US/ST=State/L=City/O=Polari/OU=CA/CN=Polari CA"

# 2. Generate Keycloak server certificate with CN=keycloak.internal
echo "2. Generating Keycloak server certificate (CN=keycloak.internal)..."
openssl genrsa -out "$CERTS_DIR/pol-kc.key" 2048

# Create config file for SAN
cat > "$CERTS_DIR/pol-kc.cnf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=State
L=City
O=Polari
OU=Keycloak
CN=keycloak.internal

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = keycloak.internal
DNS.2 = pol-keycloak
DNS.3 = localhost
EOF

# Generate CSR
openssl req -new -key "$CERTS_DIR/pol-kc.key" -out "$CERTS_DIR/pol-kc.csr" \
    -config "$CERTS_DIR/pol-kc.cnf"

# Sign with CA
openssl x509 -req -in "$CERTS_DIR/pol-kc.csr" -CA "$CA_DIR/pol-kc.crt" \
    -CAkey "$CA_DIR/pol-kc.key" -CAcreateserial -out "$CERTS_DIR/pol-kc.crt" \
    -days 825 -sha256 -extfile "$CERTS_DIR/pol-kc.cnf" -extensions v3_req

# Cleanup CSR
rm "$CERTS_DIR/pol-kc.csr" "$CERTS_DIR/pol-kc.cnf"

# 3. Generate proxy client certificate
echo "3. Generating proxy client certificate..."
openssl genrsa -out "$CLIENT_DIR/pol-kc-proxy.key" 2048

# Create config file for client cert
cat > "$CLIENT_DIR/pol-kc-proxy.cnf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=State
L=City
O=Polari
OU=Proxy
CN=polari-proxy

[v3_req]
subjectAltName = @alt_names
extendedKeyUsage = clientAuth

[alt_names]
DNS.1 = polari-proxy
DNS.2 = localhost
EOF

# Generate CSR
openssl req -new -key "$CLIENT_DIR/pol-kc-proxy.key" -out "$CLIENT_DIR/pol-kc-proxy.csr" \
    -config "$CLIENT_DIR/pol-kc-proxy.cnf"

# Sign with CA
openssl x509 -req -in "$CLIENT_DIR/pol-kc-proxy.csr" -CA "$CA_DIR/pol-kc.crt" \
    -CAkey "$CA_DIR/pol-kc.key" -CAcreateserial -out "$CERTS_DIR/pol-kc-proxy.crt" \
    -days 825 -sha256 -extfile "$CLIENT_DIR/pol-kc-proxy.cnf" -extensions v3_req

# Cleanup CSR
rm "$CLIENT_DIR/pol-kc-proxy.csr" "$CLIENT_DIR/pol-kc-proxy.cnf"

echo ""
echo "Certificate generation complete!"
echo ""
echo "Generated certificates:"
echo "  CA: $CA_DIR/pol-kc.{crt,key}"
echo "  Keycloak server: $CERTS_DIR/pol-kc.{crt,key}"
echo "  Proxy client: $CERTS_DIR/pol-kc-proxy.crt, $CLIENT_DIR/pol-kc-proxy.key"
echo ""
echo "Verifying Keycloak certificate CN..."
openssl x509 -in "$CERTS_DIR/pol-kc.crt" -noout -subject -ext subjectAltName
