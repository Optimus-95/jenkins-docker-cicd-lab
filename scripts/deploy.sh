#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/release-common.sh"

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || {
    echo "Usage: $0 <version>"
    exit 1
}

cd "$BASE_DIR"
initialize_history
load_history

OLD_ID=""
OLD_VERSION=""
if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    OLD_ID="$(docker inspect --format '{{.Image}}' "$CONTAINER_NAME")"
    OLD_VERSION="$(get_running_version)"
    [[ -n "$OLD_VERSION" ]] || {
        echo "ERROR: Cannot identify running version; refusing deployment."
        exit 1
    }

    if [[ "$VERSION" == "$OLD_VERSION" ]]; then
        echo "Version $VERSION is already running. No changes made."
        exit 0
    fi
fi

# Release versions are immutable. Never overwrite an existing version tag.
for existing in "${RELEASE_VERSIONS[@]}"; do
    if [[ "$existing" == "$VERSION" ]]; then
        echo "ERROR: Version $VERSION already exists in release history."
        echo "Choose a new version, or use rollback to select an existing release."
        exit 1
    fi
done
if docker image inspect "$IMAGE:v$VERSION" >/dev/null 2>&1; then
    echo "ERROR: Image tag $IMAGE:v$VERSION already exists; refusing to overwrite it."
    exit 1
fi

COMMIT="$(git rev-parse HEAD)"
if [[ -n "$(git status --porcelain)" ]]; then
    COMMIT="${COMMIT}-dirty"
fi

echo "===== BUILDING $IMAGE:v$VERSION ====="
docker build --build-arg "APP_VERSION=$VERSION" \
    --build-arg "GIT_COMMIT=$COMMIT" \
    -t "$IMAGE:v$VERSION" "$BASE_DIR"
NEW_ID="$(docker image inspect --format '{{.Id}}' "$IMAGE:v$VERSION")"

if [[ -n "$OLD_ID" ]]; then
    create_snapshot "$OLD_VERSION" "$OLD_ID"
fi

if ! start_and_verify "$NEW_ID" "$VERSION"; then
    echo "Deployment failed; restoring previous release."
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    if [[ -n "$OLD_ID" ]]; then
        docker run -d --name "$CONTAINER_NAME" --restart unless-stopped \
            -p "$HOST_PORT:80" "$OLD_ID" || true
        wait_healthy || true
    fi
    exit 1
fi

record_release "$VERSION" "$NEW_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$COMMIT"
prune_snapshots
echo "DEPLOYMENT SUCCESSFUL: version=$VERSION image=$NEW_ID commit=$COMMIT"
echo "URL: http://127.0.0.1:$HOST_PORT/"
