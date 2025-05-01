# Makefile for Cloud Run Ollama Gemma Service

# Available machine types for cloud-build
MACHINE_TYPES := e2-highcpu-32 e2-highcpu-16 e2-standard-8
MACHINE_TYPE ?= e2-highcpu-32

# Available GPU types for cloudrun-deploy
GPU_TYPES := nvidia-l4 nvidia-t4 nvidia-a100
GPU_TYPE ?= nvidia-l4

# Default timeout in seconds
TIMEOUT ?= 120 # Default timeout 2 minutes

# Default Gemma model if not set in .env
MODEL_NAME ?= gemma3:4b

# Load environment variables from .env file if it exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# Check if required environment variables are set
# REQUIRED_VARS := HUGGINGFACE_TOKEN PROJECT_ID REGION SERVICE_NAME REPO_NAME
# $(foreach var,$(REQUIRED_VARS),
#     $(if $(value $(var)),,
#         $(error Error: Environment variable $(var) is not set. Please check your .env file or environment.)
#     )
# )

# Define the virtual environment directory
VENV_DIR := .venv

.PHONY: help init install check-tools check-env cloud-build local-build local-run cloudrun-deploy clean

help:
	@echo "Usage: make [target] [VARIABLE=value]"
	@echo ""
	@echo "Targets:"
	@echo "  help               Show this help message."
	@echo "  init               Initialize the project: check tools, check .env, create uv environment."
	@echo "  install            Install dependencies and configure GCP settings."
	@echo "  cloud-build        Build the Docker image using Google Cloud Build."
	@echo "                     Variables: MACHINE_TYPE (default: $(MACHINE_TYPE)), MODEL_NAME (default: $(MODEL_NAME))"
	@echo "                     Available machine types: $(MACHINE_TYPES)"
	@echo "                     Supported models: gemma3:4b, gemma3:27b-it-qat, etc."
	@echo "  local-build        Build the Docker image locally on Mac M1."
	@echo "                     Variables: MODEL_NAME (default: $(MODEL_NAME))"
	@echo "                     This builds for arm64 architecture."
	@echo "  local-run          Run the locally built Docker image."
	@echo "                     Variables: MODEL_NAME (default: $(MODEL_NAME))"
	@echo "                     Automatically builds the image if it doesn't exist."
	@echo "  cloudrun-deploy    Deploy the service to Google Cloud Run."
	@echo "                     Variables: TIMEOUT (default: $(TIMEOUT)s), GPU_TYPE (default: $(GPU_TYPE))"
	@echo "                     Available GPU types: $(GPU_TYPES)"
	@echo "  clean              Remove virtual environment and __pycache__ directories."
	@echo ""
	@echo "Variables:"
	@echo "  PROJECT_ID         Your Google Cloud project ID (required, set in .env)."
	@echo "  REGION             Google Cloud region (required, set in .env)."
	@echo "  SERVICE_NAME       Cloud Run service name (required, set in .env)."
	@echo "  REPO_NAME          Artifact Registry repository name (required, set in .env)."
	@echo "  HUGGINGFACE_TOKEN  Hugging Face token (required, set in .env)."
	@echo "  MACHINE_TYPE       Cloud Build machine type (optional, default: $(MACHINE_TYPE))."
	@echo "  GPU_TYPE           Cloud Run GPU type (optional, default: $(GPU_TYPE))."
	@echo "  TIMEOUT            Cloud Run request timeout in seconds (optional, default: $(TIMEOUT))."
	@echo "  MODEL_NAME         Gemma model to use (optional, default: $(MODEL_NAME))."
	@echo "  DOCKERFILE         Dockerfile to use (optional, default: $(DOCKERFILE))."

# Check for required command-line tools
check-tools:
	@echo "Checking required tools..."
	@command -v uv >/dev/null 2>&1 || { echo >&2 "Error: uv is not installed. Please install it (e.g., 'pip install uv')."; exit 1; }
	@command -v gcloud >/dev/null 2>&1 || { echo >&2 "Error: gcloud CLI is not installed. Please install Google Cloud SDK."; exit 1; }
	@GCLOUD_VERSION=$$(gcloud version --format="value(Google Cloud SDK)" | cut -d' ' -f4); \
	if [ "$$GCLOUD_VERSION" != "519.0.0" ]; then \
		echo >&2 "Error: Google Cloud SDK version 519.0.0 is required. Current version: $$GCLOUD_VERSION"; \
		echo >&2 "Please update using: gcloud components update --version=519.0.0"; \
		exit 1; \
	fi
	@command -v curl >/dev/null 2>&1 || { echo >&2 "Error: curl is not installed."; exit 1; }
	@command -v ollama >/dev/null 2>&1 || { echo >&2 "Warning: ollama is not installed locally. It's needed inside the container."; }
	@echo "All required tools found."

# Check if .env file exists and contains required variables
check-env:
	@echo "Checking .env file..."
	@test -f .env || { echo >&2 "Error: .env file not found. Please create it from .env.example."; exit 1; }
	@for var in $(REQUIRED_VARS); do \
		grep -q "$$var=" .env || { echo >&2 "Error: Environment variable $$var is not set in .env file."; exit 1; }; \
	done
	@echo ".env file found and required variables are set."

# Initialize project with uv virtual environment
init: check-tools
	@echo "Initializing uv virtual environment..."
	@uv venv $(VENV_DIR) || { echo >&2 "Error: Failed to create virtual environment."; exit 1; }
	@echo "Virtual environment created/updated in $(VENV_DIR)"
	@echo "Project initialized. Run 'make install' next."

# Install dependencies and configure GCP
install: $(VENV_DIR)/pyvenv.cfg
	@echo "Installing dependencies using uv..."
	@uv pip sync requirements.txt --python $(VENV_DIR)/bin/python || { echo >&2 "Error: Failed to install dependencies."; exit 1; }
	@echo "Ensuring Google Cloud SDK version 519.0.0 is installed..."
	@GCLOUD_VERSION=$$(gcloud version --format="value(Google Cloud SDK)" | cut -d' ' -f4); \
	if [ "$$GCLOUD_VERSION" != "519.0.0" ]; then \
		echo "Updating Google Cloud SDK to version 519.0.0..."; \
		gcloud components update --version=519.0.0 || { echo >&2 "Error: Failed to update Google Cloud SDK to version 519.0.0."; exit 1; }; \
	fi
	@echo "Configuring Google Cloud SDK..."
	@gcloud config set project $(PROJECT_ID) || { echo >&2 "Error: Failed to set GCP project."; exit 1; }
	@gcloud config set run/region $(REGION) || { echo >&2 "Error: Failed to set GCP region."; exit 1; }
	@echo "Checking/Creating Artifact Registry repository $(REPO_NAME)..."
	@-gcloud artifacts repositories describe $(REPO_NAME) --location=$(REGION) > /dev/null 2>&1 || \
	    gcloud artifacts repositories create $(REPO_NAME) --repository-format=docker --location=$(REGION) --description="Docker repository for $(SERVICE_NAME)" || \
	    { echo >&2 "Error: Failed to create Artifact Registry repository $(REPO_NAME)."; exit 1; }
	@echo "Configuring Docker authentication for Artifact Registry...$(REGION)-docker.pkg.dev"
	@gcloud auth configure-docker $(REGION)-docker.pkg.dev || { echo >&2 "Error: Failed to configure Docker authentication."; exit 1; }
	@echo "Installation and configuration complete."

# Ensure virtualenv exists before install
$(VENV_DIR)/pyvenv.cfg:
	@echo "Virtual environment not found. Run 'make init' first."
	@exit 1

# Build Docker image using Cloud Build with parameterized machine-type and model
cloud-build:
	@echo "Building Docker image with Cloud Build..."
	@echo "Using machine type: $(MACHINE_TYPE)"
	@echo "Using model: $(MODEL_NAME)"
	@if ! echo "$(MACHINE_TYPES)" | grep -q "$(MACHINE_TYPE)"; then \
		echo >&2 "Error: Invalid machine type '$(MACHINE_TYPE)'. Available types: $(MACHINE_TYPES)"; \
		exit 1; \
	fi
	@gcloud builds submit \
		--machine-type $(MACHINE_TYPE) \
		--config=cloudbuild.yaml \
		--substitutions=_MODEL_NAME=$(MODEL_NAME),_REGION=$(REGION),_PROJECT_ID=$(PROJECT_ID),_REPO_NAME=$(REPO_NAME),_SERVICE_NAME=$(SERVICE_NAME) \
		. || { echo >&2 "Error: Cloud Build failed."; exit 1; }
	@echo "Cloud Build finished successfully."

# Build Docker image locally on Mac M1
local-build:
	@echo "Building Docker image locally from Apple Silicon ..."
	@echo "Using model: $(MODEL_NAME)"
	@echo "This will build for arm64 architecture (for local use)"
	@if [ -z "$(MODEL_NAME)" ]; then \
		echo >&2 "Error: MODEL_NAME is not set. Please set it in .env file or pass as parameter."; \
		exit 1; \
	fi
	@MODEL_TAG=$$(echo "$(MODEL_NAME)" | sed 's/:/-/g'); \
	docker build \
		--platform linux/arm64 \
		--build-arg MODEL_NAME=$(MODEL_NAME) \
		-t "ollama-gemma:$$MODEL_TAG" \
		. || { echo >&2 "Error: Local build failed."; exit 1; }
	@echo "Local build finished successfully."
	@echo "To run the container locally: make local-run"

# Build Docker image for Cloud Run (amd64 architecture)
cloud-build-local:
	@echo "Building Docker image locally for Cloud Run (amd64)..."
	@echo "Using model: $(MODEL_NAME)"
	@echo "This will build for amd64 architecture (for Cloud Run)"
	@if [ -z "$(MODEL_NAME)" ]; then \
		echo >&2 "Error: MODEL_NAME is not set. Please set it in .env file or pass as parameter."; \
		exit 1; \
	fi
	@MODEL_TAG=$$(echo "$(MODEL_NAME)" | sed 's/:/-/g'); \
	REMOTE_TAG="$(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(REPO_NAME)/ollama-gemma:$$MODEL_TAG"; \
	docker build \
		--platform linux/amd64 \
		--build-arg MODEL_NAME=$(MODEL_NAME) \
		-t "ollama-gemma-amd64:$$MODEL_TAG" \
		-t "$$REMOTE_TAG" \
		. || { echo >&2 "Error: Cloud build failed."; exit 1; }
	@echo "Cloud build finished successfully with tags: ollama-gemma-amd64:$$MODEL_TAG and $$REMOTE_TAG"

# Push the locally built Docker image to Artifact Registry
local-push:
	@echo "Pushing Docker image to Artifact Registry..."
	@echo "Using model: $(MODEL_NAME)"
	@echo "IMPORTANT: Building amd64 image for Cloud Run compatibility"
	@MODEL_TAG=$$(echo "$(MODEL_NAME)" | sed 's/:/-/g'); \
	REMOTE_TAG="$(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(REPO_NAME)/ollama-gemma:$$MODEL_TAG"; \
	$(MAKE) cloud-build-local; \
	echo "Pushing image to Artifact Registry..."; \
	docker push "$$REMOTE_TAG" || { echo >&2 "Error: Failed to push image. Make sure you're authenticated with 'gcloud auth configure-docker $(REGION)-docker.pkg.dev'"; exit 1; }; \
	echo "Image successfully pushed to Artifact Registry as $$REMOTE_TAG."

# Run the locally built Docker image
local-run:
	@echo "Running Ollama Gemma container locally..."
	@echo "Using model: $(MODEL_NAME)"
	@echo "Stopping any running Ollama container..."
	@docker stop ollama-gemma-container >/dev/null 2>&1 || true
	@MODEL_TAG=$$(echo "$(MODEL_NAME)" | sed 's/:/-/g'); \
	if ! docker image inspect "ollama-gemma:$$MODEL_TAG" > /dev/null 2>&1; then \
		echo "Image ollama-gemma:$$MODEL_TAG not found. Building it first..."; \
		$(MAKE) local-build; \
	fi; \
	echo "Starting container on http://localhost:8080"; \
	echo "Press Ctrl+C to stop the container"; \
	CONTAINER_NAME="ollama-gemma-container"; \
	if [[ "$(MODEL_NAME)" == *"27b"* || "$(MODEL_NAME)" == *"12b"* ]]; then \
		echo "Using 4-bit quantization for large model to reduce memory usage"; \
		docker run --rm --name $$CONTAINER_NAME -p 8080:8080 \
		  -e OLLAMA_FLASH_ATTENTION=1 \
		  -e OLLAMA_4BIT=1 \
		  -e OLLAMA_KV_CACHE_TYPE=q4_0 \
		  "ollama-gemma:$$MODEL_TAG"; \
	else \
		docker run --rm --name $$CONTAINER_NAME -p 8080:8080 \
		  -e OLLAMA_FLASH_ATTENTION=1 \
		  "ollama-gemma:$$MODEL_TAG"; \
	fi

# Push the locally built Docker image to Artifact Registry
local-push:
	@echo "Pushing Docker image to Artifact Registry..."
	@echo "Using model: $(MODEL_NAME)"
	@echo "IMPORTANT: Building amd64 image for Cloud Run compatibility"
	@MODEL_TAG=$$(echo "$(MODEL_NAME)" | sed 's/:/-/g'); \
	REMOTE_TAG="$(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(REPO_NAME)/ollama-gemma:$$MODEL_TAG"; \
	$(MAKE) cloud-build-local; \
	echo "Pushing image to Artifact Registry..."; \
	docker push "$$REMOTE_TAG" || { echo >&2 "Error: Failed to push image. Make sure you're authenticated with 'gcloud auth configure-docker $(REGION)-docker.pkg.dev'"; exit 1; }; \
	echo "Image successfully pushed to Artifact Registry as $$REMOTE_TAG."

# Test Ollama API with the specified model
test:
	@echo "Testing Ollama API with model: $(MODEL_NAME)"
	@echo "URL: http://localhost:8080"
	@echo -e "\nChecking model information..."
	@curl -s http://localhost:8080/api/show -d '{"model": "$(MODEL_NAME)"}' | jq .
	@echo -e "\nGenerating completion..."
	@curl -s -X POST http://localhost:8080/api/generate \
	  -H "Content-Type: application/json" \
	  -d '{"model": "$(MODEL_NAME)", "prompt": "Write a poem about Gemma3"}' | jq .

# Deploy to Cloud Run with parameterized timeout and GPU type
cloudrun-deploy:
	@echo "Deploying service $(SERVICE_NAME) to Cloud Run..."
	@echo "Using GPU type: $(GPU_TYPE) and timeout: $(TIMEOUT)s"
	@if ! echo "$(GPU_TYPES)" | grep -q "$(GPU_TYPE)"; then \
		echo >&2 "Error: Invalid GPU type '$(GPU_TYPE)'. Available types: $(GPU_TYPES)"; \
		exit 1; \
	fi
	@echo "Model being deployed: $(MODEL_NAME)"
	@MODEL_TAG=$$(echo "$(MODEL_NAME)" | sed 's/:/-/g'); \
	REMOTE_TAG="$(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(REPO_NAME)/ollama-gemma:$$MODEL_TAG"; \
	echo "Docker image tag: $$MODEL_TAG"; \
	echo "Remote image: $$REMOTE_TAG"; \
	if [[ "$(MODEL_NAME)" == *"27b"* ]]; then \
		echo "Detected 27b model, using maximum allowed resources"; \
		MEMORY=32Gi; \
		CPU=8; \
		TIMEOUT_VALUE=$(TIMEOUT); \
		CONCURRENCY=1; \
		echo "Note: Cloud Run limits memory to 32Gi for 8 CPU cores"; \
	else \
		echo "Using standard resource allocation"; \
		MEMORY=32Gi; \
		CPU=8; \
		TIMEOUT_VALUE=$(TIMEOUT); \
		CONCURRENCY=4; \
	fi; \
	gcloud run deploy $(SERVICE_NAME) \
		--image $$REMOTE_TAG \
		--region $(REGION) \
		--platform managed \
		--concurrency $$CONCURRENCY \
		--cpu $$CPU \
		--set-env-vars OLLAMA_NUM_PARALLEL=$$CONCURRENCY,OLLAMA_MODEL=$(MODEL_NAME),OLLAMA_FLASH_ATTENTION=1,OLLAMA_KV_CACHE_TYPE=q4_0 \
		--gpu 1 \
		--gpu-type $(GPU_TYPE) \
		--max-instances 1 \
		--memory $$MEMORY \
		--no-allow-unauthenticated \
		--no-cpu-throttling \
		--timeout=$$TIMEOUT_VALUE \
		--set-env-vars="HUGGING_FACE_HUB_TOKEN=$(HUGGINGFACE_TOKEN)" \
		--execution-environment=gen2 \
		|| { echo >&2 "Error: Cloud Run deployment failed."; exit 1; }
	@echo "Cloud Run deployment initiated for $(SERVICE_NAME)."

# Clean up virtual environment and __pycache__
clean:
	@echo "Cleaning up..."
	@rm -rf $(VENV_DIR)
	@find . -type d -name "__pycache__" -exec rm -rf {} +
	@echo "Cleanup complete."
