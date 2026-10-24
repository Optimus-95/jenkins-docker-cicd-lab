#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/release-common.sh"

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Usage: $0 <version>"
    exit 1
fi

cd "$BASE_DIR"
initialize_history

OLD_ID=""
OLD_VERSION=""

if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    OLD_ID="$(docker inspect --format '{{.Image}}' "$CONTAINER_NAME")"
    OLD_VERSION="$(get_running_version)"
    if [[ -z "$OLD_VERSION" ]]; then
        echo "ERROR: Cannot identify current release; refusing deployment."
        exit 1
    fi
fi

echo "===== BUILDING VERSION $VERSION ====="
docker build \
    --build-arg "APP_VERSION=$VERSION" \
    -t "$IMAGE:v$VERSION" "$BASE_DIR"

NEW_ID="$(docker image inspect --format '{{.Id}}' "$IMAGE:v$VERSION")"

if [[ -n "$OLD_ID" ]]; then
    create_snapshot "$OLD_VERSION" "$OLD_ID"
fi

echo "===== DEPLOYING VERSION $VERSION ====="
if ! start_and_verify "$NEW_ID" "$VERSION"; then
    echo "Deployment failed; attempting to restore the previous container."
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    if [[ -n "$OLD_ID" ]]; then
        docker run -d \
            --name "$CONTAINER_NAME" \
            --restart unless-stopped \
            -p "$HOST_PORT:80" "$OLD_ID" || true
        wait_healthy || true
    fi
    exit 1
fi

# Only commit the release to runtime history after successful verification.
if [[ -n "$OLD_ID" ]]; then
    save_history "$VERSION" "$NEW_ID" "$OLD_VERSION" "$OLD_ID"
else
    save_history "$VERSION" "$NEW_ID"
fi

prune_snapshots
echo "===== DEPLOYMENT SUCCESSFUL ====="
echo "Current version: $VERSION"
echo "Previous version: ${OLD_VERSION:-none}"
echo "URL: http://127.0.0.1:$HOST_PORT/"
