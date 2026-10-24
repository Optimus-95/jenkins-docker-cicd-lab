#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="cicd-demo-app"
CONTAINER_NAME="cicd-demo-app"
HOST_PORT="18080"
IMAGE="cicd-demo-app"

echo "===== AVAILABLE BACKUP IMAGES ====="

mapfile -t BACKUPS < <(
    docker image ls "$IMAGE" --format '{{.Tag}}' \
      | grep '^backup-[0-9]\{8\}-[0-9]\{6\}$' \
      | sort -r
)

if [[ "${#BACKUPS[@]}" -eq 0 ]]; then
    echo "ERROR: No backup images are available."
    echo "Deploy a version first to create a backup."
    exit 1
fi

printf '%s\n' "${BACKUPS[@]}"

TARGET_TAG="${1:-${BACKUPS[0]}}"

if [[ ! "$TARGET_TAG" =~ ^backup-[0-9]{8}-[0-9]{6}$ ]]; then
    echo "ERROR: Invalid backup tag."
    echo "Usage: $0 [backup-YYYYMMDD-HHMMSS]"
    exit 1
fi

TARGET_IMAGE="$IMAGE:$TARGET_TAG"

if ! docker image inspect "$TARGET_IMAGE" >/dev/null 2>&1; then
    echo "ERROR: Backup image not found: $TARGET_IMAGE"
    exit 1
fi

echo "===== TARGET FOR ROLLBACK ====="
echo "$TARGET_IMAGE"

CURRENT_IMAGE_ID=""
if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    CURRENT_IMAGE_ID="$(docker inspect --format '{{.Image}}' "$CONTAINER_NAME")"
fi

echo "===== RECREATING CONTAINER ====="
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

if ! docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "$HOST_PORT:80" \
    "$TARGET_IMAGE"; then

    echo "ERROR: Rollback container failed to start."

    if [[ -n "$CURRENT_IMAGE_ID" ]]; then
        docker run -d \
          --name "$CONTAINER_NAME" \
          --restart unless-stopped \
          -p "$HOST_PORT:80" \
          "$CURRENT_IMAGE_ID" || true
    fi

    exit 1
fi

echo "===== WAITING FOR HEALTH ====="
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
    echo "ERROR: Rolled-back container did not become healthy."
    docker logs "$CONTAINER_NAME" || true
    exit 1
fi

echo "===== VERIFYING WEB RESPONSE ====="
curl --fail --silent --show-error "http://127.0.0.1:$HOST_PORT/" >/dev/null

echo "===== ROLLBACK SUCCESSFUL ====="
docker ps --filter "name=^/$CONTAINER_NAME$"
