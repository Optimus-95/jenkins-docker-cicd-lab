#!/usr/bin/env bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${STATE_DIR:-$BASE_DIR/.runtime}"
HISTORY_FILE="$STATE_DIR/releases.tsv"

IMAGE="cicd-demo-app"
CONTAINER_NAME="cicd-demo-app"
HOST_PORT="18080"

mkdir -p "$STATE_DIR"

get_running_version() {
    curl --fail --silent --show-error \
        "http://127.0.0.1:$HOST_PORT/" |
        grep -oE 'Version: [0-9]+(\.[0-9]+){1,2}' |
        head -n 1 | awk '{print $2}'
}

load_history() {
    RELEASE_VERSIONS=()
    RELEASE_IDS=()

    if [[ -f "$HISTORY_FILE" ]]; then
        while IFS=$'\t' read -r version image_id; do
            [[ -n "${version:-}" && -n "${image_id:-}" ]] || continue
            RELEASE_VERSIONS+=("$version")
            RELEASE_IDS+=("$image_id")
        done < "$HISTORY_FILE"
    fi
}

save_history() {
    local temp_file="$HISTORY_FILE.tmp.$$"
    : > "$temp_file"

    while [[ $# -ge 2 ]]; do
        printf '%s\t%s\n' "$1" "$2" >> "$temp_file"
        shift 2
    done

    mv "$temp_file" "$HISTORY_FILE"
}

initialize_history() {
    load_history
    if [[ ${#RELEASE_VERSIONS[@]} -gt 0 ]]; then
        return 0
    fi

    if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
        local version image_id
        version="$(get_running_version)" || {
            echo "ERROR: Cannot determine the running application version."
            return 1
        }
        image_id="$(docker inspect --format '{{.Image}}' "$CONTAINER_NAME")"
        save_history "$version" "$image_id"
        echo "Initialized release history from running version $version."
    fi
}

create_snapshot() {
    local version="$1"
    local image_id="$2"
    local snapshot_tag

    snapshot_tag="rollback-$(date +%Y%m%d-%H%M%S)-v$version"
    docker image tag "$image_id" "$IMAGE:$snapshot_tag"
    echo "Rollback snapshot created: $IMAGE:$snapshot_tag"
}

prune_snapshots() {
    # Remove legacy backup tags from the previous backup strategy.
    # Version tags such as v1.0 and v1.4 remain untouched.
    local legacy=()
    mapfile -t legacy < <(
        docker image ls "$IMAGE" --format '{{.Tag}}' |
        grep -E '^backup-[0-9]{8}-[0-9]{6}$' || true
    )

    local tag
    for tag in "${legacy[@]}"; do
        docker image rm "$IMAGE:$tag" || true
    done

    local snapshots=()
    mapfile -t snapshots < <(
        docker image ls "$IMAGE" --format '{{.Tag}}' |
        grep -E '^rollback-[0-9]{8}-[0-9]{6}-v[0-9]+(\.[0-9]+){1,2}$' |
        sort -r || true
    )

    local i
    for ((i=2; i<${#snapshots[@]}; i++)); do
        docker image rm "$IMAGE:${snapshots[$i]}" || true
    done

    echo "Retained rollback snapshots: $((${#snapshots[@]} < 2 ? ${#snapshots[@]} : 2))"
}

wait_healthy() {
    local attempt status health
    for attempt in $(seq 1 30); do
        status="$(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)"
        health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER_NAME" 2>/dev/null || true)"

        if [[ "$status" == "running" && "$health" == "healthy" ]]; then
            return 0
        fi

        if [[ "$status" != "running" ]]; then
            break
        fi
        sleep 2
    done

    docker logs "$CONTAINER_NAME" 2>/dev/null || true
    echo "ERROR: Container did not become healthy."
    return 1
}

start_and_verify() {
    local image_id="$1"
    local expected_version="$2"

    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    if ! docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "$HOST_PORT:80" \
        "$image_id"; then
        echo "ERROR: Container failed to start."
        return 1
    fi

    wait_healthy || return 1

    if ! get_running_version | grep -Fx "$expected_version" >/dev/null; then
        echo "ERROR: HTTP response does not match expected version $expected_version."
        return 1
    fi
}
