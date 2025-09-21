#!/bin/bash

# Debug script for container readiness issues
# Run this on the computer where containers are running

set -euo pipefail

# Get the wiki name from command line or use default
WIKI_NAME="${1:-testsite}"
CONTAINER_NAME="bluespice-${WIKI_NAME}-wiki-web"

echo "=== Container Readiness Debug Report ==="
echo "Wiki Name: $WIKI_NAME"
echo "Expected Container Name: $CONTAINER_NAME"
echo "Date: $(date)"
echo ""

echo "=== 1. Check if container exists ==="
if docker ps -a --filter name="$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"; then
    echo "✓ Container found"
else
    echo "❌ Container not found"
    echo ""
    echo "Available containers with 'bluespice' in name:"
    docker ps -a --filter name="bluespice" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "No BlueSpice containers found"
    echo ""
    echo "All running containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    exit 1
fi

echo ""
echo "=== 2. Check container status ==="
RUNNING_STATUS=$(docker ps --filter name="$CONTAINER_NAME" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$" && echo "RUNNING" || echo "NOT_RUNNING")
echo "Container Status: $RUNNING_STATUS"

if [[ "$RUNNING_STATUS" == "NOT_RUNNING" ]]; then
    echo ""
    echo "Container details:"
    docker ps -a --filter name="$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}"
    echo ""
    echo "Recent container logs:"
    docker logs --tail 20 "$CONTAINER_NAME" 2>&1 || echo "Could not retrieve logs"
    exit 1
fi

echo ""
echo "=== 3. Check container health ==="
HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "none")
echo "Health Status: $HEALTH_STATUS"

echo ""
echo "=== 4. Test container command execution ==="
if docker exec "$CONTAINER_NAME" echo "ready" >/dev/null 2>&1; then
    echo "✓ Container can execute commands"
else
    echo "❌ Container cannot execute commands"
    echo "Trying with different approaches..."
    
    echo "- Testing basic shell access:"
    if docker exec "$CONTAINER_NAME" /bin/sh -c "echo 'shell test'" 2>&1; then
        echo "✓ Shell access works"
    else
        echo "❌ Shell access failed"
    fi
    
    echo "- Testing as root:"
    if docker exec --user root "$CONTAINER_NAME" echo "root test" 2>&1; then
        echo "✓ Root access works"
    else
        echo "❌ Root access failed"
    fi
fi

echo ""
echo "=== 5. Check container processes ==="
echo "Running processes in container:"
docker exec "$CONTAINER_NAME" ps aux 2>/dev/null || echo "Could not list processes"

echo ""
echo "=== 6. Check volume mounts ==="
echo "Container volume mounts:"
docker inspect "$CONTAINER_NAME" --format='{{range .Mounts}}{{.Source}} -> {{.Destination}} ({{.Type}}){{println}}{{end}}' 2>/dev/null || echo "Could not retrieve mount info"

echo ""
echo "=== 7. Check network connectivity ==="
echo "Container network settings:"
docker inspect "$CONTAINER_NAME" --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}}: {{$v.IPAddress}}{{println}}{{end}}' 2>/dev/null || echo "Could not retrieve network info"

echo ""
echo "=== 8. Recent container logs ==="
echo "Last 30 lines of container logs:"
docker logs --tail 30 "$CONTAINER_NAME" 2>&1 || echo "Could not retrieve logs"

echo ""
echo "=== Debug Report Complete ==="
