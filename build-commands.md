### Build Commands
Use Docker Compose to build and run your application for the desired environment.

# Dev
This is the default build.
docker compose up --build

# Test
docker compose -f docker-compose-test.yml up --build