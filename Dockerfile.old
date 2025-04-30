# Use a specific Ollama version for consistency (matches notebook)
FROM ollama/ollama:0.5.5 as builder

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    git \
    git-lfs \
    curl \
    ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Build argument for Hugging Face token
ARG HF_TOKEN
ENV HUGGING_FACE_HUB_TOKEN=${HF_TOKEN}
ENV HF_HUB_ENABLE_HF_TRANSFER=1

# Install huggingface_hub CLI tool first for download
RUN pip3 install --no-cache-dir huggingface_hub

# Create directory for Ollama models inside the container
RUN mkdir -p /ollama_models

# Download the Gemma adapter model using the HF token
# Note: This requires the HF_TOKEN to be passed during the build
RUN echo "Downloading Gemma adapter model from Hugging Face..." && \
    huggingface-cli download google-cloud-partnership/gemma-2-2b-it-lora-sql \ 
        --local-dir /ollama_models/gemma-2-2b-it-lora-sql \ 
        --local-dir-use-symlinks=false \
        --token ${HUGGING_FACE_HUB_TOKEN} || \
    (echo "Error: Failed to download model. Check HF_TOKEN and network." && exit 1)

# --- Final Stage ---
FROM ollama/ollama:0.5.5

# Install Python and runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 python3-pip curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy application code and requirements
WORKDIR /app
COPY . /app

# Install Python dependencies
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy downloaded models from builder stage
COPY --from=builder /ollama_models /ollama_models

# Copy the Ollama Modelfile
COPY ollama_config/gemma-2-2b-it-lora-sql.modelfile /gemma-2-2b-it-lora-sql.modelfile

# Set environment variables for Ollama and FastAPI
ENV OLLAMA_HOST=0.0.0.0:11434
ENV OLLAMA_MODELS=/ollama_models
ENV OLLAMA_KEEP_ALIVE=-1
ENV OLLAMA_DEBUG=false
ENV PORT=8080 # Default port for Cloud Run
ENV AIP_HTTP_PORT=8080 # For Vertex AI compatibility if needed later
ENV PYTHONUNBUFFERED=1 # Ensure Python logs appear in Cloud Run logs

# Create the Ollama model using the Modelfile
# This runs ollama serve temporarily, creates the model, then stops it.
# Increased sleep duration for potentially slow model creation.
RUN ollama serve & \
    sleep 15 && \
    echo "Creating Ollama model gemma-2-2b-it-lora-sql..." && \
    ollama create gemma-2-2b-it-lora-sql -f /gemma-2-2b-it-lora-sql.modelfile && \
    echo "Model created." && \
    pkill ollama || \
    (echo "Error during Ollama model creation." && exit 1)

# Expose Ollama internal port and the application port
EXPOSE 11434
EXPOSE 8080

# Make entrypoint script executable
RUN chmod +x /app/entrypoint.sh

# Set the entrypoint script
ENTRYPOINT ["/app/entrypoint.sh"]
