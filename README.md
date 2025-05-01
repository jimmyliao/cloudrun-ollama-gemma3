# Cloud Run Ollama Gemma3 Service

A project for deploying Ollama with Gemma3 models on Google Cloud Run with GPU support, with optimized local development on Mac M1.

## Overview

This project provides a containerized Ollama service running Gemma3 models on Google Cloud Run with GPU acceleration. It supports multiple model sizes (4b, 12b, 27b) and includes optimizations for both local development on Mac M1 and cloud deployment. The project uses a single Dockerfile with flexible model selection and memory optimizations like Flash Attention and 4-bit quantization.

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
   MODEL_NAME=gemma3:4b  # Default model, can be changed to gemma3:27b-it-qat
   ```

## Usage with Makefile

The project includes a Makefile to simplify common tasks for both local development and cloud deployment:

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

### Local Development on Mac M1

#### Build for Local Development (arm64)

```bash
make local-build
```

This builds a Docker image optimized for Mac M1 (arm64) architecture with the model specified in your .env file. The image is tagged as `ollama-gemma:<model-tag>` where `<model-tag>` is the model name with colons replaced by hyphens (e.g., `gemma3:12b-it-qat` becomes `gemma3-12b-it-qat`).

#### Run Locally

```bash
make local-run
```

This runs the locally built image, automatically applying optimizations:
- Flash Attention for all models
- 4-bit quantization for larger models (12b, 27b)
- Proper container naming for easy management
- Stops any existing container before starting a new one

#### Test the Local Service

```bash
make test
```

This tests the running service by checking model information and generating a completion using the API endpoints.

### Cloud Deployment

#### Build for Cloud Run (amd64)

```bash
make cloud-build-local
```

This builds a Docker image specifically for Cloud Run (amd64 architecture). The image is tagged with both a local name (`ollama-gemma-amd64:<model-tag>`) and the full Artifact Registry path in one step.

#### Push to Artifact Registry

```bash
make local-push
```

This builds an amd64 image (using `cloud-build-local`) and pushes it to Google Artifact Registry. The image is consistently tagged as `<region>-docker.pkg.dev/<project-id>/<repo-name>/ollama-gemma:<model-tag>`.

#### Deploy to Cloud Run

```bash
make cloudrun-deploy
```

This deploys the image to Cloud Run with appropriate resources based on model size:
- 27b models: 32Gi memory, 8 CPUs, concurrency=1
- Other models: 32Gi memory, 8 CPUs, concurrency=4

All deployments include optimizations:
- Flash Attention
- KV Cache optimization

The deployment uses the exact same image reference as created by `local-push` for consistency.

### Supported Models

- gemma3:4b
- gemma3:12b-it-qat
- gemma3:27b-it-qat

You can specify the model in your .env file or pass it as a parameter:

```bash
make local-run MODEL_NAME=gemma3:12b-it-qat
```

### Deploy to Cloud Run with GPU

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

## Architecture and Optimizations

### Cross-Platform Architecture

This project supports both local development on Mac M1 (arm64) and cloud deployment on Google Cloud Run (amd64):

- **Local Development**: Uses arm64 architecture for Mac M1 compatibility
- **Cloud Deployment**: Uses amd64 architecture for Cloud Run compatibility

### Memory Optimizations

Larger models (12b, 27b) include several memory optimizations:

- **Flash Attention**: `OLLAMA_FLASH_ATTENTION=1` - Improves attention mechanism efficiency
- **4-bit Quantization**: `OLLAMA_4BIT=1` - Reduces memory usage by using 4-bit precision
- **KV Cache Optimization**: `OLLAMA_KV_CACHE_TYPE=q4_0` - Optimizes key-value cache storage

These optimizations allow running larger models on hardware with limited memory.

### Local Model Repository

The system uses a local model repository approach instead of pulling from the official Ollama site:

1. Creates a Modelfile with the specified model during build
2. At runtime, checks for models in the artifact repository
3. Creates models from local Modelfiles if needed
4. Includes fallback mechanisms for model creation failures

This approach works in air-gapped environments and provides better control over model versions.

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
# For default gemma3:4b model
gcloud builds submit \
  --config=cloudbuild.yaml \
  --machine-type e2-highcpu-32 \
  --substitutions=_MODEL_NAME=gemma3:4b,_REGION=YOUR_REGION,_PROJECT_ID=YOUR_PROJECT_ID,_REPO_NAME=YOUR_REPO_NAME,_SERVICE_NAME=YOUR_SERVICE_NAME \
  .

# For gemma3:27b-it-qat model
gcloud builds submit \
  --config=cloudbuild.yaml \
  --machine-type e2-highcpu-32 \
  --substitutions=_MODEL_NAME=gemma3:27b-it-qat,_REGION=YOUR_REGION,_PROJECT_ID=YOUR_PROJECT_ID,_REPO_NAME=YOUR_REPO_NAME,_SERVICE_NAME=YOUR_SERVICE_NAME \
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

The project uses a single Dockerfile that supports multiple model configurations via the `MODEL_NAME` build argument.

The Dockerfile is based on the official Ollama image and configures:
- Exposed port 8080
- Model storage in /models
- Reduced logging verbosity
- Persistent model loading
- Pre-loaded Gemma3 model (configurable via MODEL_NAME)

You can specify different models by setting the MODEL_NAME in your .env file or passing it as a parameter to the Makefile.

Supported models include:
- gemma3:4b (default)
- gemma3:27b-it-qat
- Other Gemma3 models available via Ollama

## References

- [Cloud Run GPU with Gemma and Ollama Tutorial](https://cloud.google.com/run/docs/tutorials/gpu-gemma-with-ollama)
- [Ollama Documentation](https://ollama.ai/docs)
- [Gemma3 Model Information](https://huggingface.co/google/gemma3-4b)
