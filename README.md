# Cloud Run Ollama Gemma3 Service

A project for deploying Ollama with Gemma3 models on Google Cloud Run with GPU support.

## Overview

This project provides a containerized Ollama service running Gemma3 models on Google Cloud Run with GPU acceleration. It includes a Dockerfile for building the container image and a Makefile to simplify the deployment process.

## Prerequisites

- [uv](https://github.com/astral-sh/uv) for Python virtual environment management
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) version 519.0.0
- [curl](https://curl.se/) for testing the deployed service
- [Ollama](https://ollama.ai/) (optional for local testing)
- A Google Cloud Platform account with billing enabled
- A Hugging Face account with API token

## Setup

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd cloudrun-ollama-gemma3
   ```

2. Create a `.env` file based on the example:
   ```bash
   cp .env.example .env
   ```

3. Edit the `.env` file and fill in your configuration:
   ```
   HUGGINGFACE_TOKEN=your_huggingface_token
   PROJECT_ID=your_gcp_project_id
   REGION=your_preferred_region
   SERVICE_NAME=your_service_name
   REPO_NAME=your_repository_name
   ```

## Usage with Makefile

The project includes a Makefile to simplify common tasks:

### Initialize the Project

```bash
make init
```

This will:
- Check for required tools (uv, gcloud, curl, ollama)
- Verify Google Cloud SDK version is 519.0.0
- Create a virtual environment using uv

### Install Dependencies and Configure GCP

```bash
make install
```

This will:
- Update the virtual environment with required packages
- Ensure Google Cloud SDK version 519.0.0 is installed
- Configure your GCP project and region
- Create an Artifact Registry repository if it doesn't exist
- Configure Docker authentication for Artifact Registry

### Build the Docker Image

```bash
make cloud-build
```

Or with a specific machine type:

```bash
make cloud-build MACHINE_TYPE=e2-highcpu-16
```

Available machine types:
- e2-highcpu-32 (default)
- e2-highcpu-16
- e2-standard-8

### Deploy to Cloud Run

```bash
make cloudrun-deploy
```

Or with specific GPU type and timeout:

```bash
make cloudrun-deploy GPU_TYPE=nvidia-l4 TIMEOUT=180
```

Available GPU types:
- nvidia-l4 (default)
- nvidia-t4
- nvidia-a100

### Clean Up

```bash
make clean
```

This removes the virtual environment and Python cache files.

## Manual Deployment

If you prefer to run the commands manually or need more control over the process, you can use the following gcloud commands:

### 1. Configure your GCP project and region

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud config set run/region YOUR_REGION
```

### 2. Create an Artifact Registry repository

```bash
gcloud artifacts repositories create YOUR_REPO_NAME \
  --repository-format=docker \
  --location=YOUR_REGION \
  --description="Docker repository for Ollama Gemma service"
```

### 3. Build the Docker image using Cloud Build

```bash
gcloud builds submit \
  --tag YOUR_REGION-docker.pkg.dev/YOUR_PROJECT_ID/YOUR_REPO_NAME/YOUR_SERVICE_NAME \
  --machine-type e2-highcpu-32 \
  .
```

### 4. Deploy to Cloud Run with GPU

```bash
gcloud run deploy YOUR_SERVICE_NAME \
  --image YOUR_REGION-docker.pkg.dev/YOUR_PROJECT_ID/YOUR_REPO_NAME/YOUR_SERVICE_NAME \
  --region YOUR_REGION \
  --platform managed \
  --concurrency 4 \
  --cpu 8 \
  --set-env-vars OLLAMA_NUM_PARALLEL=4 \
  --gpu 1 \
  --gpu-type nvidia-l4 \
  --max-instances 1 \
  --memory 32Gi \
  --no-allow-unauthenticated \
  --no-cpu-throttling \
  --timeout=120 \
  --set-env-vars="HUGGING_FACE_HUB_TOKEN=YOUR_HUGGINGFACE_TOKEN" \
  --execution-environment=gen2
```

## Testing the Deployed Service

After deployment, you can test your service using curl. If you've configured the service with `--no-allow-unauthenticated`, you'll need to include an authentication token:

```bash
# Get an ID token for authentication (only needed if --no-allow-unauthenticated was used)
TOKEN=$(gcloud auth print-identity-token)

# Send a request to the service with authentication
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model": "gemma3:4b", "prompt": "Write a poem about Gemma3"}' \
  https://YOUR_SERVICE_NAME-HASH.a.run.app/api/generate
```

If you've allowed unauthenticated access, you can use a simpler command:

```bash
# Example of a direct request to the generate API
curl https://YOUR_SERVICE_NAME-HASH.a.run.app/api/generate -d '{
  "model": "gemma3:4b",
  "prompt": "Write a poem about Gemma3"
}'
```

Note that the Ollama API endpoint is `/api/generate` for text generation.

## Dockerfile Details

The Dockerfile is based on the official Ollama image and configures:
- Exposed port 8080
- Model storage in /models
- Reduced logging verbosity
- Persistent model loading
- Pre-loaded Gemma3 4B model

## References

- [Cloud Run GPU with Gemma and Ollama Tutorial](https://cloud.google.com/run/docs/tutorials/gpu-gemma-with-ollama)
- [Ollama Documentation](https://ollama.ai/docs)
- [Gemma3 Model Information](https://huggingface.co/google/gemma3-4b)
