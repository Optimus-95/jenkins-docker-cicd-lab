#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/release-common.sh"

TARGET_REQUESTED="${1:-}"
initialize_history
load_history

if (( ${#RELEASE_VERSIONS[@]} < 2 )); then
    echo "ERROR: At least two successful releases are needed for rollback."
    exit 1
fi

CURRENT_VERSION="$(get_running_version)"
CURRENT_ID="$(docker inspect --format '{{.Image}}' "$CONTAINER_NAME")"
TARGET_INDEX=-1

if [[ -z "$TARGET_REQUESTED" ]]; then
    TARGET_INDEX=1
else
    for i in "${!RELEASE_VERSIONS[@]}"; do
        if [[ "${RELEASE_VERSIONS[$i]}" == "$TARGET_REQUESTED" ]]; then
            TARGET_INDEX="$i"
            break
        fi
    done
fi

if (( TARGET_INDEX < 0 )); then
    echo "ERROR: Requested release '$TARGET_REQUESTED' is not in history."
    echo "Available releases:"
    printf '  %s\n' "${RELEASE_VERSIONS[@]}"
    exit 1
fi

TARGET_VERSION="${RELEASE_VERSIONS[$TARGET_INDEX]}"
TARGET_ID="${RELEASE_IDS[$TARGET_INDEX]}"
TARGET_TIME="${RELEASE_TIMES[$TARGET_INDEX]}"
TARGET_COMMIT="${RELEASE_COMMITS[$TARGET_INDEX]}"

if [[ "$TARGET_VERSION" == "$CURRENT_VERSION" ]]; then
    echo "Version $TARGET_VERSION is already running. Nothing to do."
    exit 0
fi
docker image inspect "$TARGET_ID" >/dev/null 2>&1 || {
    echo "ERROR: Target image is missing: $TARGET_ID"
    exit 1
}

echo "Current release: $CURRENT_VERSION"
echo "Rollback target: $TARGET_VERSION"
create_snapshot "$CURRENT_VERSION" "$CURRENT_ID"

if ! start_and_verify "$TARGET_ID" "$TARGET_VERSION"; then
    echo "Rollback failed; restoring $CURRENT_VERSION."
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker run -d --name "$CONTAINER_NAME" --restart unless-stopped \
        -p "$HOST_PORT:80" "$CURRENT_ID" || true
    wait_healthy || true
    exit 1
fi

# Promote the selected release; the displaced current release becomes second.
record_release "$TARGET_VERSION" "$TARGET_ID" "$TARGET_TIME" "$TARGET_COMMIT"
prune_snapshots
echo "ROLLBACK SUCCESSFUL: now running $TARGET_VERSION"
