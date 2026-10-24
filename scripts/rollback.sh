#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/release-common.sh"

initialize_history
load_history

if [[ ${#RELEASE_VERSIONS[@]} -lt 2 ]]; then
    echo "ERROR: No previous successful release is recorded."
    echo "Deploy another version before testing rollback."
    exit 1
fi

CURRENT_VERSION="$(get_running_version)"
CURRENT_ID="$(docker inspect --format '{{.Image}}' "$CONTAINER_NAME")"
TARGET_VERSION="${RELEASE_VERSIONS[1]}"
TARGET_ID="${RELEASE_IDS[1]}"

if ! docker image inspect "$TARGET_ID" >/dev/null 2>&1; then
    echo "ERROR: Previous release image is missing: $TARGET_ID"
    exit 1
fi

echo "Current release: $CURRENT_VERSION"
echo "Rollback target: $TARGET_VERSION"

create_snapshot "$CURRENT_VERSION" "$CURRENT_ID"

if ! start_and_verify "$TARGET_ID" "$TARGET_VERSION"; then
    echo "Rollback failed; attempting to restore $CURRENT_VERSION."
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "$HOST_PORT:80" "$CURRENT_ID" || true
    wait_healthy || true
    exit 1
fi

# Swap the two entries: the replaced release remains available for roll-forward.
save_history "$TARGET_VERSION" "$TARGET_ID" "$CURRENT_VERSION" "$CURRENT_ID"
prune_snapshots

echo "===== ROLLBACK SUCCESSFUL ====="
echo "Current version: $TARGET_VERSION"
echo "Previous version available for roll-forward: $CURRENT_VERSION"
