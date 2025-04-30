# Makefile for Cloud Run Ollama Gemma Service

# Available machine types for cloud-build
MACHINE_TYPES := e2-highcpu-32 e2-highcpu-16 e2-standard-8
MACHINE_TYPE ?= e2-highcpu-32

# Available GPU types for cloudrun-deploy
GPU_TYPES := nvidia-l4 nvidia-t4 nvidia-a100
GPU_TYPE ?= nvidia-l4

# Default timeout in seconds
TIMEOUT ?= 3600 # Default timeout 1 hour

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

.PHONY: help init install check-tools check-env cloud-build cloudrun-deploy clean

help:
	@echo "Usage: make [target] [VARIABLE=value]"
	@echo ""
	@echo "Targets:"
	@echo "  help               Show this help message."
	@echo "  init               Initialize the project: check tools, check .env, create uv environment."
	@echo "  install            Install dependencies and configure GCP settings."
	@echo "  cloud-build        Build the Docker image using Google Cloud Build."
	@echo "                     Variables: MACHINE_TYPE (default: $(MACHINE_TYPE))"
	@echo "                     Available types: $(MACHINE_TYPES)"
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

# Check for required command-line tools
check-tools:
	@echo "Checking required tools..."
	@command -v uv >/dev/null 2>&1 || { echo >&2 "Error: uv is not installed. Please install it (e.g., 'pip install uv')."; exit 1; }
	@command -v gcloud >/dev/null 2>&1 || { echo >&2 "Error: gcloud CLI is not installed. Please install Google Cloud SDK."; exit 1; }
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
	@echo "Configuring Google Cloud SDK..."
	@gcloud config set project $(PROJECT_ID) || { echo >&2 "Error: Failed to set GCP project."; exit 1; }
	@gcloud config set run/region $(REGION) || { echo >&2 "Error: Failed to set GCP region."; exit 1; }
	@echo "Checking/Creating Artifact Registry repository $(REPO_NAME)..."
	@-gcloud artifacts repositories describe $(REPO_NAME) --location=$(REGION) > /dev/null 2>&1 || \
	    gcloud artifacts repositories create $(REPO_NAME) --repository-format=docker --location=$(REGION) --description="Docker repository for $(SERVICE_NAME)" || \
	    { echo >&2 "Error: Failed to create Artifact Registry repository $(REPO_NAME)."; exit 1; }
	@echo "Configuring Docker authentication for Artifact Registry..."
	@gcloud auth configure-docker $(REGION)-docker.pkg.dev || { echo >&2 "Error: Failed to configure Docker authentication."; exit 1; }
	@echo "Installation and configuration complete."

# Ensure virtualenv exists before install
$(VENV_DIR)/pyvenv.cfg:
	@echo "Virtual environment not found. Run 'make init' first."
	@exit 1

# Build Docker image using Cloud Build with parameterized machine-type
cloud-build:
	@echo "Building Docker image with Cloud Build..."
	@echo "Using machine type: $(MACHINE_TYPE)"
	@if ! echo "$(MACHINE_TYPES)" | grep -q "$(MACHINE_TYPE)"; then \
		echo >&2 "Error: Invalid machine type '$(MACHINE_TYPE)'. Available types: $(MACHINE_TYPES)"; \
		exit 1; \
	fi
	@gcloud builds submit \
		--tag $(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(REPO_NAME)/$(SERVICE_NAME) \
		--machine-type $(MACHINE_TYPE) \
		. || { echo >&2 "Error: Cloud Build failed."; exit 1; }
	@echo "Cloud Build finished successfully."

# Deploy to Cloud Run with parameterized timeout and GPU type
cloudrun-deploy:
	@echo "Deploying service $(SERVICE_NAME) to Cloud Run..."
	@echo "Using GPU type: $(GPU_TYPE) and timeout: $(TIMEOUT)s"
	@if ! echo "$(GPU_TYPES)" | grep -q "$(GPU_TYPE)"; then \
		echo >&2 "Error: Invalid GPU type '$(GPU_TYPE)'. Available types: $(GPU_TYPES)"; \
		exit 1; \
	fi
	@gcloud run deploy $(SERVICE_NAME) \
		--image $(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(REPO_NAME)/$(SERVICE_NAME) \
		--region $(REGION) \
		--platform managed \
		--concurrency 4 \
		--cpu 8 \
		--set-env-vars OLLAMA_NUM_PARALLEL=4 \
		--gpu 1 \
		--gpu-type $(GPU_TYPE) \
		--max-instances 1 \
		--memory 32Gi \
		--no-allow-unauthenticated \
		--no-cpu-throttling \
		--timeout=$(TIMEOUT) \
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
