#!/bin/bash
# Fetches the latest BlueSpice version from Docker Hub

get_latest_version() {
    local latest_version
    
    # Query Docker Hub API for bluespice/wiki tags
    latest_version=$(curl -s "https://hub.docker.com/v2/repositories/bluespice/wiki/tags/?page_size=100" | \
        grep -o '"name":"[0-9]\+\.[0-9]\+\.[0-9]\+"' | \
        grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | \
        sort -V | \
        tail -1)
    
    if [ -n "$latest_version" ]; then
        echo "$latest_version"
        return 0
    else
        # Fallback to cached version or default
        if [ -f "$SCRIPT_DIR/BLUESPICE_VERSION" ]; then
            cat "$SCRIPT_DIR/BLUESPICE_VERSION"
        else
            echo "5.1.3"
        fi
        return 1
    fi
}

get_latest_version
