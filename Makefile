# Load environment variables from .env file
# This will overwrite any shell-exported variables with the same name
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# Define variables (allow overriding from .env or command line)
PROJECT_ID ?= $(PROJECT_ID)
REGION ?= $(REGION)
SERVICE_NAME ?= ollama-gemma-rag-agent
IMAGE_NAME ?= ollama-gemma-rag-image
REPOSITORY_NAME ?= ollama-gemma-repo # Artifact Registry repo name
HF_TOKEN ?= $(HF_TOKEN)

# Construct full image URI
IMAGE_URI = $(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(REPOSITORY_NAME)/$(IMAGE_NAME):latest

# Define python interpreter
PYTHON = python3

# Phony targets (targets that are not files)
.PHONY: init build deploy clean help all

# Default target
all: help

## --------------------
## Setup & Initialization
## --------------------
init: check-env ## Alias for check-env

check-env:
	@echo "--- Checking Environment Variables ---"
	@if [ ! -f .env ]; then \
		echo "'.env' file not found. Copying '.env.example' to '.env'."; \
		cp .env.example .env; \
		echo "Please fill in the required values (HF_TOKEN, PROJECT_ID, REGION) in the '.env' file."; \
		exit 1; \
	fi
	@$(PYTHON) -c 'import sys; from helper import check_env_vars; sys.exit(0) if check_env_vars() else sys.exit(1)'
	@echo "---------------------------------------"

## --------------------
## Build Process
## --------------------
build: init
	@echo "--- Building Docker Image via Cloud Build ---"
	@if [ -z "$(HF_TOKEN)" ]; then \
		echo "Error: HF_TOKEN is not set in your .env file or environment."; \
		exit 1; \
	fi
	@echo "Configuring Docker for Artifact Registry: $(REGION)-docker.pkg.dev"
	@gcloud auth configure-docker $(REGION)-docker.pkg.dev --quiet
	@echo "Ensuring Artifact Registry Repository '$(REPOSITORY_NAME)' exists..."
	@gcloud artifacts repositories create $(REPOSITORY_NAME) --project=$(PROJECT_ID) --location=$(REGION) --repository-format=docker --quiet || echo "Repository '$(REPOSITORY_NAME)' already exists or failed to create (permission issue?). Continuing build..."
	@echo "Submitting build to Cloud Build..."
	@echo "Image URI: $(IMAGE_URI)"
	@gcloud builds submit . --tag $(IMAGE_URI) --project=$(PROJECT_ID) \
		--build-arg=HF_TOKEN=$(HF_TOKEN) \
		--machine-type=e2-highcpu-8 \
		--timeout=45m
	@echo "Cloud Build submitted. Monitor progress in the GCP console."
	@echo "---------------------------------------------"

## --------------------
## Deployment Process
## --------------------
deploy: init # Depends on init for variables, assumes image is built (implicitly by build target usually run first)
	@echo "--- Deploying to Cloud Run ---"
	@if [ -z "$(PROJECT_ID)" ] || [ -z "$(REGION)" ] || [ -z "$(SERVICE_NAME)" ]; then \
		echo "Error: PROJECT_ID, REGION, or SERVICE_NAME is not set."; \
		exit 1; \
	fi
	@echo "Deploying service '$(SERVICE_NAME)' to region '$(REGION)' using image '$(IMAGE_URI)'"
	@gcloud run deploy $(SERVICE_NAME) \
		--image=$(IMAGE_URI) \
		--project=$(PROJECT_ID) \
		--region=$(REGION) \
		--platform=managed \
		--port=8080 \
		--allow-unauthenticated \
		--cpu=2 \
		--memory=8Gi \
		--concurrency=2 \
		--timeout=600s \
		--min-instances=0 \
		--max-instances=2 \
		--execution-environment=gen2 
	@echo "-----------------------------"

## --------------------
## Utility Targets
## --------------------
clean:
	@echo "--- Cleaning up (Placeholder) ---"
	@# Add commands to remove local build artifacts if any (e.g., __pycache__)
	@find . -name '__pycache__' -exec rm -rf {} + 
	@find . -name '*.pyc' -exec rm -f {} + 
	@echo "Cleanup complete."

help:
	@echo "Available commands:"
	@echo "  make init          Check .env file and required variables (HF_TOKEN, PROJECT_ID, REGION)."
	@echo "  make build         Build the Docker image using Google Cloud Build."
	@echo "  make deploy        Deploy the built image to Google Cloud Run."
	@echo "  make clean         Remove temporary Python cache files."
	@echo "  make all           Show this help message (default)."
