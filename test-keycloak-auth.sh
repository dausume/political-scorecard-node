#!/bin/bash

# Get token from Keycloak and test protected endpoint
echo "Getting token from Keycloak..."

# Get the token and extract access_token using jq
TOKEN=$(curl -s -X POST 'http://localhost:8080/realms/Political-Scorecard/protocol/openid-connect/token' \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d 'client_id=political-scorecard-frontend' \
    -d 'username=testuser' \
    -d 'password=password' \
    -d 'grant_type=password' | jq -r '.access_token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "Failed to get token. Is Keycloak running?"
    exit 1
fi

echo "Token obtained successfully!"
echo "Testing protected endpoint..."
echo

# Use the token to call the protected endpoint
curl -H "Authorization: Bearer $TOKEN" \
    http://localhost:8580/auth/test-auth

echo
