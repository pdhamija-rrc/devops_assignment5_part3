
#!/bin/bash

# Yarrow-Mullein Bank Application
# Module 6 - Part 1: Automated Docker Compose Deployment

set -Eeuo pipefail

# --------------------------------------------------
# 1. Define project paths and logging
# --------------------------------------------------

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$PROJECT_DIR/deployment.log"
INSPECT_FILE="$PROJECT_DIR/nginx-logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

exec > >(tee -a "$LOG_FILE") 2>&1

log "Starting Yarrow-Mullein Bank deployment"

# --------------------------------------------------
# 2. Validate prerequisites
# --------------------------------------------------

for command in docker curl jq ss; do
    if ! command -v "$command" >/dev/null 2>&1; then
        log "ERROR: $command is not installed."
        exit 1
    fi
done

if ! docker info >/dev/null 2>&1; then
    log "ERROR: Docker is not running or accessible."
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    log "ERROR: Docker Compose is unavailable."
    exit 1
fi

log "Docker, Compose, curl, jq and ss are available."

# --------------------------------------------------
# 3. Validate deployment directory
# --------------------------------------------------

cd "$PROJECT_DIR"

log "Working directory: $PROJECT_DIR"

if [[ ! -f docker-compose.yml ]]; then
    log "ERROR: docker-compose.yml not found."
    exit 1
fi

docker compose config -q

log "Docker Compose configuration is valid."

# --------------------------------------------------
# 4. Validate required ports
# Allow existing containers from this project
# --------------------------------------------------

for port in 80 3000 5000; do

    if ss -ltnH "( sport = :$port )" | grep -q .; then

        case "$port" in
            80) service="nginx" ;;
            3000) service="transactions" ;;
            5000) service="backend" ;;
        esac

        container_id="$(docker compose ps -q "$service")"

        if [[ -n "$container_id" ]] &&
           [[ "$(docker inspect -f '{{.State.Running}}' "$container_id")" == "true" ]]; then

            log "Port $port is already used by this project's $service container. Reusing it."

        else
            log "ERROR: Port $port is occupied by another application."
            exit 1
        fi

    else
        log "Port $port is available."
    fi

done

# --------------------------------------------------
# 5. Build and deploy services
# --------------------------------------------------

log "Building and starting Docker services..."

docker compose up --build -d

log "Docker Compose deployment completed."

# --------------------------------------------------
# 6. Display running containers
# --------------------------------------------------

log "Running Docker containers:"

docker ps

# --------------------------------------------------
# 7. Display Docker images
# --------------------------------------------------

log "Available Docker images:"

docker images

# --------------------------------------------------
# 8. Collect Nginx container ID
# --------------------------------------------------

NGINX_CONTAINER_ID="$(docker compose ps -q nginx)"

if [[ -z "$NGINX_CONTAINER_ID" ]]; then
    log "ERROR: Nginx container was not found."
    exit 1
fi

if [[ "$(docker inspect -f '{{.State.Running}}' "$NGINX_CONTAINER_ID")" != "true" ]]; then
    log "ERROR: Nginx container is not running."
    exit 1
fi

log "Nginx container ID: $NGINX_CONTAINER_ID"

# --------------------------------------------------
# 9. Application health checks
# --------------------------------------------------

check_url() {

    local url="$1"
    local attempts=30

    log "Checking $url"

    for ((i=1; i<=attempts; i++)); do

        if curl --fail --silent "$url" >/dev/null 2>&1; then
            log "Health check passed: $url"
            return 0
        fi

        sleep 2
    done

    log "ERROR: Health check failed: $url"
    return 1
}

# Check Nginx
check_url "http://localhost/"

# --------------------------------------------------
# 10. Check Transactions API
# --------------------------------------------------

check_transactions() {

    log "Checking Transactions API..."

    local response

    response="$(curl --silent --output /dev/null \
        --write-out "%{http_code}" \
        http://localhost:3000/api/transactions/not-a-valid-id)"

    if [[ "$response" == "400" ]]; then
        log "Health check passed: Transactions API is responding."
    else
        log "ERROR: Transactions API returned HTTP $response."
        return 1
    fi
}

check_transactions

# Check Backend
check_url "http://localhost:5000/"

# --------------------------------------------------
# 11. Inspect Nginx image
# --------------------------------------------------

log "Inspecting nginx:alpine image..."

if ! docker image inspect nginx:alpine >/dev/null 2>&1; then
    log "ERROR: nginx:alpine image was not found."
    exit 1
fi

docker image inspect nginx:alpine > "$INSPECT_FILE"

log "Nginx inspection saved to $INSPECT_FILE"

# --------------------------------------------------
# 12. Extract image information using jq
# --------------------------------------------------

log "Extracting Nginx image information..."

jq '.[0] | {
    RepoTags: .RepoTags,
    Created: .Created,
    Os: .Os,
    Config: .Config,
    ExposedPorts: .Config.ExposedPorts
}' "$INSPECT_FILE"

# --------------------------------------------------
# 13. Final deployment status
# --------------------------------------------------

log "All deployment checks completed successfully."
log "Yarrow-Mullein Bank Application deployment finished."

