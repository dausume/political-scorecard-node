#!/bin/bash
set -e

# Political Scorecard (PSC) Certificate Generator
# For standalone PSC deployment or as part of Polari Suite
#
# Can be called directly or from parent generate-pol-certs.sh
# When called from parent, accepts args to bypass interactive prompts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================
# Supports both positional args (for direct use) and flags (for parent call)
#
# Direct usage:   ./generate-psc-certs.sh [dev|prod|cleanup]
# Parent call:    ./generate-psc-certs.sh prod --parent-call --server-ip=<IP> [--shared-ca=<path>]
# ==============================================================================

ENV="${1:-dev}"
PARENT_CALL=false
SERVER_IP=""
SHARED_CA_DIR=""

# Parse additional arguments
shift || true  # Shift past the environment arg if it exists
while [[ $# -gt 0 ]]; do
    case $1 in
        --parent-call)
            PARENT_CALL=true
            shift
            ;;
        --server-ip=*)
            SERVER_IP="${1#*=}"
            shift
            ;;
        --shared-ca=*)
            SHARED_CA_DIR="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [[ "$ENV" != "dev" && "$ENV" != "prod" && "$ENV" != "cleanup" ]]; then
    echo "Usage: $0 [dev|prod|cleanup] [options]"
    echo ""
    echo "Environments:"
    echo "  dev     - Development environment (localhost, self-signed)"
    echo "  prod    - Production environment (psc.polari-systems.org)"
    echo "  cleanup - Remove all existing certificates and keys"
    echo ""
    echo "Options (for parent script integration):"
    echo "  --parent-call         Script is being called from parent orchestrator"
    echo "  --server-ip=<IP>      Server IPv6 address (required for prod with --parent-call)"
    echo "  --shared-ca=<PATH>    Path to shared CA directory (uses existing CA instead of generating)"
    exit 1
fi

# Directory structure
CERTS_DIR="$SCRIPT_DIR/psc-proxy/certs"
CA_DIR="$CERTS_DIR/ca"

# Handle cleanup
if [[ "$ENV" == "cleanup" ]]; then
    echo "Cleaning up PSC certificates..."

    if [[ -d "$CERTS_DIR" ]]; then
        rm -rf "$CERTS_DIR"
        mkdir -p "$CERTS_DIR"
        echo "  - Cleaned $CERTS_DIR"
    fi

    echo ""
    echo "Cleanup complete. Run '$0 dev' or '$0 prod' to generate new certificates."
    exit 0
fi

echo "============================================"
echo "PSC Certificate Generator"
echo "Environment: $ENV"
if [[ "$PARENT_CALL" == "true" ]]; then
    echo "Mode: Called from parent orchestrator"
fi
echo "============================================"
echo ""

# Environment-specific configuration
if [[ "$ENV" == "dev" ]]; then
    CA_SUBJ="/C=US/ST=State/L=City/O=Polari/OU=PSC/CN=PSC Dev CA"
    PROXY_CN="localhost"
    PROXY_SANS="DNS.1 = localhost
DNS.2 = psc-proxy
DNS.3 = host.docker.internal
DNS.4 = *.localhost"
    SERVER_IP=""
else
    # Production environment
    if [[ "$PARENT_CALL" == "true" ]]; then
        # Called from parent - use provided values, no prompts
        if [[ -z "$SERVER_IP" ]]; then
            echo "Error: --server-ip is required for production mode with --parent-call"
            exit 1
        fi
        echo "Using server IP from parent: $SERVER_IP"
    else
        # Direct call - show warning and prompt
        echo ""
        echo "WARNING: Production certificates should only be generated on the production server itself."
        echo "         Do not run this on a development machine."
        echo ""
        read -p "Are you running this on the production server? (yes/no): " CONFIRM
        if [[ "$CONFIRM" != "yes" ]]; then
            echo "Aborting. Please run this script on the production server."
            exit 1
        fi

        read -p "Enter the server's public IPv6 address: " SERVER_IP
        if [[ -z "$SERVER_IP" ]]; then
            echo "Error: IPv6 address is required for production."
            exit 1
        fi
    fi

    CA_SUBJ="/C=US/ST=VA/L=Arlington/O=Polari/OU=PSC/CN=psc.polari-systems.org CA"
    PROXY_CN="psc.polari-systems.org"
    PROXY_SANS="DNS.1 = psc.polari-systems.org
DNS.2 = api.psc.polari-systems.org
DNS.3 = psc-proxy
IP.1 = $SERVER_IP"
fi

# Create directory structure
mkdir -p "$CA_DIR"

# Check if we should use a shared CA
if [[ -n "$SHARED_CA_DIR" && -f "$SHARED_CA_DIR/pol-ca.crt" && -f "$SHARED_CA_DIR/pol-ca.key" ]]; then
    echo "1. Using shared CA from: $SHARED_CA_DIR"
    USE_SHARED_CA=true
    CA_CRT="$SHARED_CA_DIR/pol-ca.crt"
    CA_KEY="$SHARED_CA_DIR/pol-ca.key"
    # Copy CA to local directory for reference
    cp "$CA_CRT" "$CA_DIR/psc-ca.crt"
    cp "$CA_KEY" "$CA_DIR/psc-ca.key"
    chmod 600 "$CA_DIR/psc-ca.key"
    echo "   Shared CA copied to: $CA_DIR/"
else
    echo "1. Generating CA certificate..."
    USE_SHARED_CA=false
    CA_CRT="$CA_DIR/psc-ca.crt"
    CA_KEY="$CA_DIR/psc-ca.key"
    openssl genrsa -out "$CA_KEY" 4096
    openssl req -new -x509 -days 3650 -key "$CA_KEY" -out "$CA_CRT" \
        -subj "$CA_SUBJ"
    echo "   CA certificate created: $CA_CRT"
fi

echo ""
echo "2. Generating PSC Proxy certificate (CN=$PROXY_CN)..."
openssl genrsa -out "$CERTS_DIR/psc-proxy.key" 2048

cat > "$CERTS_DIR/psc-proxy.cnf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=VA
L=Arlington
O=Polari
OU=PSC
CN=$PROXY_CN

[v3_req]
subjectAltName = @alt_names

[alt_names]
$PROXY_SANS
EOF

openssl req -new -key "$CERTS_DIR/psc-proxy.key" -out "$CERTS_DIR/psc-proxy.csr" \
    -config "$CERTS_DIR/psc-proxy.cnf"

openssl x509 -req -in "$CERTS_DIR/psc-proxy.csr" -CA "$CA_CRT" \
    -CAkey "$CA_KEY" -CAcreateserial -out "$CERTS_DIR/psc-proxy.crt" \
    -days 825 -sha256 -extfile "$CERTS_DIR/psc-proxy.cnf" -extensions v3_req

rm "$CERTS_DIR/psc-proxy.csr" "$CERTS_DIR/psc-proxy.cnf"
chmod 600 "$CERTS_DIR/psc-proxy.key"
echo "   Proxy certificate created: $CERTS_DIR/psc-proxy.crt"

echo ""
echo "============================================"
echo "PSC Certificate generation complete!"
echo "============================================"
echo ""
echo "Generated certificates:"
echo "  CA:    $CA_DIR/psc-ca.{crt,key}"
echo "  Proxy: $CERTS_DIR/psc-proxy.{crt,key}"
echo ""
echo "Verifying proxy certificate:"
openssl x509 -in "$CERTS_DIR/psc-proxy.crt" -noout -subject -ext subjectAltName
