FROM ollama/ollama:latest

# Define model as a build argument with default value
# This will be overridden by the Makefile/cloudbuild.yaml based on .env settings
# ARG MODEL_NAME=gemma3:4b
ARG MODEL_NAME

# Listen on all interfaces, port 8080
ENV OLLAMA_HOST=0.0.0.0:8080

# Store model weight files in /models
ENV OLLAMA_MODELS=/models

# Reduce logging verbosity
ENV OLLAMA_DEBUG=false

# Never unload model weights from the GPU
ENV OLLAMA_KEEP_ALIVE=-1

# Store the model weights in the container image
ENV MODEL=${MODEL_NAME}

# Print the model being used for verification
RUN echo "Building container with model: ${MODEL_NAME}"

# Create model directory and prepare for local model storage
RUN mkdir -p /models

# Create a modelfile for the specified model
RUN echo "FROM ${MODEL_NAME}" > /models/Modelfile

# Print the model being prepared
RUN echo "Prepared Modelfile for model: ${MODEL_NAME}"

# Create a startup script to handle model loading at runtime
COPY startup.sh /startup.sh
RUN chmod 755 /startup.sh

# Start Ollama with the startup script
ENTRYPOINT ["/startup.sh"]