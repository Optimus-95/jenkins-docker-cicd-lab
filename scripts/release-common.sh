#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$BASE_DIR/config.env" ]]; then
    source "$BASE_DIR/config.env"
fi

IMAGE="${IMAGE:-cicd-demo-app}"
CONTAINER_NAME="${CONTAINER_NAME:-cicd-demo-app}"
HOST_PORT="${HOST_PORT:-18080}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-http://127.0.0.1:${HOST_PORT}/}"
MAX_ROLLBACK_SNAPSHOTS="${MAX_ROLLBACK_SNAPSHOTS:-2}"
MAX_RELEASES="${MAX_RELEASES:-10}"
STATE_DIR="${STATE_DIR:-${JENKINS_HOME:-$HOME}/.local/state/jenkins-docker-cicd-lab}"
HISTORY_FILE="$STATE_DIR/releases.tsv"

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

get_running_version() {
    curl --fail --silent --show-error "$HEALTHCHECK_URL" |
        grep -oE 'Version: [0-9]+(\.[0-9]+){1,2}' |
        head -n 1 | awk '{print $2}'
}

load_history() {
    RELEASE_VERSIONS=()
    RELEASE_IDS=()
    RELEASE_TIMES=()
    RELEASE_COMMITS=()
    [[ -f "$HISTORY_FILE" ]] || return 0

    local version image_id timestamp commit extra
    while IFS=$'\t' read -r version image_id timestamp commit extra; do
        [[ -n "${version:-}" && -n "${image_id:-}" ]] || continue
        RELEASE_VERSIONS+=("$version")
        RELEASE_IDS+=("$image_id")
        RELEASE_TIMES+=("${timestamp:-unknown}")
        RELEASE_COMMITS+=("${commit:-unknown}")
    done < "$HISTORY_FILE"
}

save_history() {
    local tmp="$HISTORY_FILE.tmp.$$"
    : > "$tmp"
    while [[ $# -ge 4 ]]; do
        printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$tmp"
        shift 4
    done
    chmod 600 "$tmp"
    mv "$tmp" "$HISTORY_FILE"
}

record_release() {
    local version="$1" image_id="$2" timestamp="$3" commit="$4"
    local i
    local versions=("$version")
    local ids=("$image_id")
    local times=("$timestamp")
    local commits=("$commit")

    load_history
    for ((i=0; i<${#RELEASE_VERSIONS[@]}; i++)); do
        [[ "${RELEASE_VERSIONS[$i]}" == "$version" ]] && continue
        versions+=("${RELEASE_VERSIONS[$i]}")
        ids+=("${RELEASE_IDS[$i]}")
        times+=("${RELEASE_TIMES[$i]}")
        commits+=("${RELEASE_COMMITS[$i]}")
    done

    [[ "$MAX_RELEASES" =~ ^[0-9]+$ ]] && (( MAX_RELEASES >= 1 )) || {
        echo "ERROR: MAX_RELEASES must be a positive integer."
        return 1
    }

    local args=()
    for ((i=0; i<${#versions[@]} && i<MAX_RELEASES; i++)); do
        args+=("${versions[$i]}" "${ids[$i]}" "${times[$i]}" "${commits[$i]}")
    done
    save_history "${args[@]}"
    echo "Release history updated: $version"
}

initialize_history() {
    load_history
    if (( ${#RELEASE_VERSIONS[@]} > 0 )); then
        return 0
    fi

    if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
        local version image_id
        version="$(get_running_version)" || {
            echo "ERROR: Cannot determine running application version."
            return 1
        }
        image_id="$(docker inspect --format '{{.Image}}' "$CONTAINER_NAME")"
        record_release "$version" "$image_id" "unknown" "unknown"
    fi
}

image_commit() {
    local value
    value="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$1" 2>/dev/null || true)"
    [[ -n "$value" && "$value" != "<no value>" ]] || value="unknown"
    printf '%s' "$value"
}

create_snapshot() {
    local tag="rollback-$(date -u +%Y%m%d-%H%M%S)-v$1"
    docker image tag "$2" "$IMAGE:$tag"
    echo "Snapshot created: $IMAGE:$tag"
}

prune_snapshots() {
    [[ "$MAX_ROLLBACK_SNAPSHOTS" =~ ^[0-9]+$ ]] &&
        (( MAX_ROLLBACK_SNAPSHOTS >= 1 )) || {
        echo "ERROR: MAX_ROLLBACK_SNAPSHOTS must be a positive integer."
        return 1
    }

    local snapshots=()
    mapfile -t snapshots < <(
        docker image ls "$IMAGE" --format '{{.Tag}}' |
        grep -E '^rollback-[0-9]{8}-[0-9]{6}-v[0-9]+(\.[0-9]+){1,2}$' |
        sort -r || true
    )
    local i
    for ((i=MAX_ROLLBACK_SNAPSHOTS; i<${#snapshots[@]}; i++)); do
        docker image rm "$IMAGE:${snapshots[$i]}" || true
    done
    echo "Rollback snapshots retained: $(( ${#snapshots[@]} < MAX_ROLLBACK_SNAPSHOTS ? ${#snapshots[@]} : MAX_ROLLBACK_SNAPSHOTS ))"
}

wait_healthy() {
    local attempt status health
    for attempt in $(seq 1 30); do
        status="$(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true)"
        health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER_NAME" 2>/dev/null || true)"
        [[ "$status" == running && "$health" == healthy ]] && return 0
        [[ "$status" == running ]] || break
        sleep 2
    done
    docker logs "$CONTAINER_NAME" 2>/dev/null || true
    echo "ERROR: Container did not become healthy."
    return 1
}

start_and_verify() {
    local image_id="$1" expected_version="$2"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker run -d --name "$CONTAINER_NAME" --restart unless-stopped \
        -p "$HOST_PORT:80" "$image_id" || return 1
    wait_healthy || return 1
    local actual
    actual="$(get_running_version)" || return 1
    [[ "$actual" == "$expected_version" ]] || {
        echo "ERROR: Expected version $expected_version, received $actual."
        return 1
    }
}
