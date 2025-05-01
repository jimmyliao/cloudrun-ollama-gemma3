#!/bin/bash

# Check if Ollama is running locally (non-Docker)
if command -v ollama >/dev/null 2>&1; then
    echo "Checking for local Ollama instances..."
    if pgrep -x "ollama" >/dev/null; then
        echo "Found local Ollama process. Stopping it..."
        pkill -f ollama
        sleep 2
        echo "Local Ollama process stopped."
    fi
fi

# Check for Docker containers running Ollama
echo "Checking for Docker containers running Ollama..."

# First check for our specific named container
if docker ps --filter "name=ollama-gemma-container" --format "{{.ID}}" 2>/dev/null | grep -q .; then
    echo "Found ollama-gemma-container. Stopping it..."
    docker stop ollama-gemma-container >/dev/null 2>&1
    echo "Container stopped."
fi

# Then check for any other Ollama containers
CONTAINERS=$(docker ps --filter "ancestor=ollama/ollama" --format "{{.ID}}" 2>/dev/null)
CONTAINERS="$CONTAINERS $(docker ps --filter "name=ollama" --format "{{.ID}}" 2>/dev/null)"
CONTAINERS="$CONTAINERS $(docker ps --filter "ancestor=ollama-gemma" --format "{{.ID}}" 2>/dev/null)"

if [ -n "$CONTAINERS" ]; then
    echo "Found Docker containers running Ollama. Stopping them..."
    for CONTAINER in $CONTAINERS; do
        echo "Stopping container $CONTAINER..."
        docker stop $CONTAINER >/dev/null 2>&1
    done
    echo "All Ollama containers stopped."
fi

# Check if port 8080 is still in use
if lsof -ti :8080 >/dev/null 2>&1; then
    echo "Port 8080 is still in use. Attempting to free it..."
    PID=$(lsof -ti :8080)
    echo "Process using port 8080: $PID"
    kill -9 $PID 2>/dev/null
    sleep 1
    if lsof -ti :8080 >/dev/null 2>&1; then
        echo "Failed to free port 8080. Please manually kill the process."
        exit 1
    fi
    echo "Successfully freed port 8080."
fi

echo "Ready to start Ollama container."
