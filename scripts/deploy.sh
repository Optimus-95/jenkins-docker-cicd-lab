#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="cicd-demo-app"
CONTAINER_NAME="cicd-demo-app"
HOST_PORT="18080"
IMAGE="cicd-demo-app"
VERSION="${1:-}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.1"
    exit 1
fi

cd "$BASE_DIR"

echo "===== BUILDING VERSION $VERSION ====="
docker build \
    --build-arg "APP_VERSION=$VERSION" \
    -t "$IMAGE:v$VERSION" \
    "$BASE_DIR"

NEW_IMAGE="$IMAGE:v$VERSION"

if ! docker image inspect "$NEW_IMAGE" >/dev/null 2>&1; then
    echo "ERROR: New image was not created."
    exit 1
fi

if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo "ERROR: Existing container $CONTAINER_NAME not found."
    echo "Refusing deployment because there is no current version to restore."
    exit 1
fi

OLD_IMAGE_ID="$(docker inspect --format '{{.Image}}' "$CONTAINER_NAME")"
BACKUP_TAG="backup-$(date +%Y%m%d-%H%M%S)"
BACKUP_IMAGE="$IMAGE:$BACKUP_TAG"

echo "===== BACKING UP CURRENT IMAGE ====="
docker image tag "$OLD_IMAGE_ID" "$BACKUP_IMAGE"
echo "Backup created: $BACKUP_IMAGE"

echo "===== REPLACING DEMO CONTAINER ====="
docker rm -f "$CONTAINER_NAME"

if ! docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "$HOST_PORT:80" \
    "$NEW_IMAGE"; then

    echo "ERROR: New container failed to start. Restoring previous image."
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "$HOST_PORT:80" \
        "$OLD_IMAGE_ID"
    exit 1
fi

echo "===== WAITING FOR HEALTH CHECK ====="
HEALTHY=0

for attempt in $(seq 1 30); do
    STATUS="$(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)"
    HEALTH="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER_NAME" 2>/dev/null || true)"

    if [[ "$STATUS" == "running" && "$HEALTH" == "healthy" ]]; then
        HEALTHY=1
        break
    fi

    if [[ "$STATUS" != "running" ]]; then
        break
    fi

    sleep 2
done

if [[ "$HEALTHY" -ne 1 ]]; then
    echo "ERROR: New version failed health check. Rolling back."
    docker logs "$CONTAINER_NAME" || true
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "$HOST_PORT:80" \
        "$OLD_IMAGE_ID"

    echo "Rollback attempted. Check container health."
    exit 1
fi

echo "===== VERIFYING RESPONSE ====="
if ! curl --fail --silent --show-error "http://127.0.0.1:$HOST_PORT/" \
    | grep -F "Version: $VERSION" >/dev/null; then

    echo "ERROR: Version response did not match. Rolling back."
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "$HOST_PORT:80" \
        "$OLD_IMAGE_ID"

    exit 1
fi

echo "===== KEEPING LATEST TWO BACKUPS ====="
docker image ls --format '{{.Tag}}' "$IMAGE" \
    | grep '^backup-[0-9]\{8\}-[0-9]\{6\}$' \
    | sort -r \
    | tail -n +3 \
    | while read -r old_tag; do
        [[ -n "$old_tag" ]] && docker image rm "$IMAGE:$old_tag" || true
      done

echo "===== DEPLOYMENT SUCCESSFUL ====="
echo "Image: $NEW_IMAGE"
echo "Backup: $BACKUP_IMAGE"
echo "URL: http://127.0.0.1:$HOST_PORT/"
docker ps --filter "name=^/$CONTAINER_NAME$"
