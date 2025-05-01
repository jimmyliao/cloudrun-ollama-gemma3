#!/bin/bash

# This script handles model loading at runtime for the Ollama service

# Function to handle local Modelfile fallback
goto_local_modelfile() {
    echo "Trying to create model from local Modelfile"
    if [ -f "/models/Modelfile" ]; then
        echo "Found Modelfile at /models/Modelfile"
        cd /models && ollama create "$MODEL" -f Modelfile
        if ollama list | grep -q "$MODEL"; then
            echo "Successfully created model $MODEL from local Modelfile"
        else
            echo "Error: Failed to create model $MODEL from local Modelfile"
            
            # If the model name contains a colon, try using the exact model name from the Modelfile
            if [[ "$MODEL" == *":"* ]]; then
                MODEL_NAME_EXACT=$(cat /models/Modelfile | grep "FROM" | cut -d' ' -f2)
                echo "Attempting to create model with exact name: $MODEL_NAME_EXACT"
                cd /models && ollama create "$MODEL_NAME_EXACT" -f Modelfile
                if ollama list | grep -q "$MODEL_NAME_EXACT"; then
                    echo "Successfully created model $MODEL_NAME_EXACT from Modelfile"
                    export MODEL="$MODEL_NAME_EXACT"
                else
                    echo "Error: Failed to create model with exact name"
                    create_fallback_model
                fi
            else
                create_fallback_model
            fi
        fi
    else
        echo "Error: No Modelfile found at /models/Modelfile"
        create_fallback_model
    fi
}

# Function to create fallback model
create_fallback_model() {
    echo "Creating a basic gemma3:4b model as fallback"
    mkdir -p /models
    echo "FROM gemma3:4b" > /models/Modelfile.fallback
    cd /models && ollama create "gemma3:4b" -f Modelfile.fallback
    export MODEL="gemma3:4b"
}

# Enable verbose logging
set -x

# Print system information for debugging
echo "=== SYSTEM INFORMATION ==="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo "Memory: $(free -h)"
echo "Disk: $(df -h /)"
if [ -e /dev/nvidia0 ]; then
    echo "GPU detected: $(nvidia-smi --query-gpu=name --format=csv,noheader)"
    echo "GPU memory: $(nvidia-smi --query-gpu=memory.total --format=csv,noheader)"
else
    echo "No GPU detected"
fi

# Print environment variables
echo "=== ENVIRONMENT VARIABLES ==="
echo "MODEL environment variable: $MODEL"
echo "OLLAMA_MODEL environment variable: $OLLAMA_MODEL"
echo "OLLAMA_HOST: $OLLAMA_HOST"
echo "OLLAMA_MODELS: $OLLAMA_MODELS"
echo "OLLAMA_DEBUG: $OLLAMA_DEBUG"
echo "OLLAMA_KEEP_ALIVE: $OLLAMA_KEEP_ALIVE"
echo "OLLAMA_NUM_PARALLEL: $OLLAMA_NUM_PARALLEL"

# If OLLAMA_MODEL is set, use it to override the MODEL environment variable
if [ -n "$OLLAMA_MODEL" ]; then
    echo "Using OLLAMA_MODEL: $OLLAMA_MODEL"
    export MODEL=$OLLAMA_MODEL
else
    echo "Using default MODEL: $MODEL"
fi

echo "Final model to be used: $MODEL"

# Start Ollama server in the background
echo "=== STARTING OLLAMA SERVER ==="
ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to start
echo "Waiting for Ollama server to start..."
sleep 10

# Check if Ollama server is running
if ps -p $OLLAMA_PID > /dev/null; then
    echo "Ollama server started successfully with PID $OLLAMA_PID"
else
    echo "Error: Ollama server failed to start"
    exit 1
fi

# Check if the model is already available
echo "=== CHECKING FOR MODEL ==="
if ollama list | grep -q "$MODEL"; then
    echo "Model $MODEL is already available"
else
    # Normalize model name for artifact repository path
    MODEL_NORMALIZED=$(echo "$MODEL" | sed 's/:/-/g')
    ARTIFACT_PATH="/models/$MODEL_NORMALIZED"
    
    echo "Checking for model in artifact repository at $ARTIFACT_PATH"
    if [ -d "$ARTIFACT_PATH" ] && [ -f "$ARTIFACT_PATH/Modelfile" ]; then
        echo "Found model in artifact repository"
        cd "$ARTIFACT_PATH" && ollama create "$MODEL" -f Modelfile
        if ollama list | grep -q "$MODEL"; then
            echo "Successfully created model $MODEL from artifact repository"
        else
            echo "Error: Failed to create model from artifact repository"
            # Try with exact name from Modelfile
            MODEL_NAME_EXACT=$(cat "$ARTIFACT_PATH/Modelfile" | grep "FROM" | cut -d' ' -f2)
            echo "Attempting with exact name: $MODEL_NAME_EXACT"
            cd "$ARTIFACT_PATH" && ollama create "$MODEL_NAME_EXACT" -f Modelfile
            if ollama list | grep -q "$MODEL_NAME_EXACT"; then
                echo "Successfully created model $MODEL_NAME_EXACT"
                export MODEL="$MODEL_NAME_EXACT"
            else
                echo "Error: Failed with exact name too"
                # Fall back to local Modelfile
                echo "Falling back to local Modelfile"
                goto_local_modelfile
            fi
        fi
    else
        echo "Model not found in artifact repository"
        goto_local_modelfile
    fi
fi

# List available models
echo "=== AVAILABLE MODELS AFTER INITIALIZATION ==="
ollama list

# Disable verbose logging
set +x

echo "=== OLLAMA SERVER READY ==="
echo "Service is now ready to accept requests"

# Keep the script running by waiting for the Ollama process
wait $OLLAMA_PID
