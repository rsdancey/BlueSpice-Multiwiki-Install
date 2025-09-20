#!/bin/bash

# Docker utilities for BlueSpice MediaWiki deployment
# Provides consistent Docker container management functions

set -euo pipefail

# Get standardized container name
get_container_name() {
    local wiki_name="$1"
    echo "bluespice-${wiki_name}-wiki-web"
}

# Wait for container to be ready and healthy
wait_for_container_ready() {
    local wiki_name="$1"
    local timeout="${2:-60}"
    local container_name
    container_name=$(get_container_name "$wiki_name")
    local max_attempts=$((timeout / 2))
    local attempt=1
    
    echo "Waiting for container $container_name to be ready..."
    
    while [[ $attempt -le $max_attempts ]]; do
        # Check if container exists and is running
        if docker ps --filter name="$container_name" --format "{{.Names}}" | grep -q "^${container_name}$"; then
            # Check if container is healthy (if health check is configured)
            local health_status
            health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")
            
            if [[ "$health_status" == "healthy" ]] || [[ "$health_status" == "none" ]]; then
                # Additional check: ensure container can execute commands
                if docker exec "$container_name" test -f /data/bluespice/post-init-settings.php 2>/dev/null; then
                    echo "✓ Container $container_name is ready and operational"
                    return 0
                fi
            fi
        fi
        
        echo "⏳ Waiting for container readiness (attempt $attempt/$max_attempts)..."
        sleep 2
        ((attempt++))
    done
    
    echo "❌ Container $container_name failed to become ready within ${timeout}s" >&2
    return 1
}

# Check if container is running
is_container_running() {
    local wiki_name="$1"
    local container_name
    container_name=$(get_container_name "$wiki_name")
    
    docker ps --filter name="$container_name" --format "{{.Names}}" | grep -q "^${container_name}$"
}

# Execute command in container with error checking
docker_exec_safe() {
    local wiki_name="$1"
    shift
    local container_name
    container_name=$(get_container_name "$wiki_name")
    
    if ! is_container_running "$wiki_name"; then
        echo "❌ Container $container_name is not running" >&2
        return 1
    fi
    
    docker exec "$container_name" "$@"
}

# Copy file to container with error checking
docker_copy_to_container() {
    local wiki_name="$1"
    local source_path="$2"
    local dest_path="$3"
    local container_name
    container_name=$(get_container_name "$wiki_name")
    
    if ! is_container_running "$wiki_name"; then
        echo "❌ Container $container_name is not running" >&2
        return 1
    fi
    
    if [[ ! -e "$source_path" ]]; then
        echo "❌ Source path does not exist: $source_path" >&2
        return 1
    fi
    
    docker cp "$source_path" "$container_name:$dest_path"
}
