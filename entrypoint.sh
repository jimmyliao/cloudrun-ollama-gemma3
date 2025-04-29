#!/bin/bash
set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ENTRYPOINT: $1"
}

# Start Ollama server in the background
log "Starting Ollama server..."
ollama serve & 
OLLAMA_PID=$!

# Wait a bit for Ollama to start
log "Waiting for Ollama to initialize (15 seconds)..."
sleep 15

# Check if Ollama process is still running
if ! kill -0 $OLLAMA_PID > /dev/null 2>&1; then
    log "ERROR: Ollama process failed to start or exited prematurely."
    exit 1
fi

# Optional: Basic health check (adjust URL/port if needed)
log "Performing basic health check on Ollama (http://localhost:11434)..."
if curl --fail --silent --show-error http://localhost:11434 > /dev/null; then
    log "✅ Ollama responded to health check."
else
    log "⚠️ WARNING: Ollama did not respond to health check within the wait period. Continuing..."
    # Consider adding more robust checks or longer waits if needed
fi

# Start the FastAPI application using Uvicorn
# It will listen on the host and port defined by the PORT env var (set to 8080 in Dockerfile)
log "Starting FastAPI application on port ${PORT:-8080}..."
uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}

# If uvicorn exits, script finishes. Keep Ollama running if needed?
# Depending on setup, might need 'wait $OLLAMA_PID' if uvicorn failure shouldn't stop container
log "FastAPI application exited."
