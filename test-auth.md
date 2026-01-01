curl -X POST 'http://localhost:8080/realms/Political-Scorecard/protocol/openid-connect/token' \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d 'client_id=political-scorecard-frontend' \
    -d 'username=testuser' \
    -d 'password=password' \
    -d 'grant_type=password'