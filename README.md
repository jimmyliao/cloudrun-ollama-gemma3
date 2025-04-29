# Ollama + Gemma 2 + RAG Agent on Cloud Run

This project deploys a Retrieval-Augmented Generation (RAG) agent using Ollama, the Gemma 2 model (specifically the `gemma-2-2b-it-lora-sql` adapter), LangChain, and LangGraph, serving it via FastAPI on Google Cloud Run.

It replicates the core functionality of the [vertex_ai_ollama_gemma2_rag_agent.ipynb](https://github.com/GoogleCloudPlatform/generative-ai/blob/main/open-models/serving/vertex_ai_ollama_gemma2_rag_agent.ipynb) notebook but structures it for deployment using Docker and Make.

## Prerequisites

1.  **Google Cloud SDK (`gcloud`)**: Installed and authenticated. ([Installation Guide](https://cloud.google.com/sdk/docs/install))
2.  **Docker**: Installed and running. ([Installation Guide](https://docs.docker.com/engine/install/))
3.  **Make**: Standard build automation tool (usually pre-installed on Linux/macOS).
4.  **Hugging Face Account & Token**: 
    *   Create an account on [Hugging Face Hub](https://huggingface.co/).
    *   Accept the license/terms for the [Gemma model](https://huggingface.co/google/gemma-2b) (or the specific adapter if needed).
    *   Generate a User Access Token with **read** permissions. ([Generate Token](https://huggingface.co/settings/tokens))
5.  **GCP Project Setup**:
    *   A Google Cloud Project with billing enabled.
    *   Enable the following APIs:
        *   Cloud Build API (`cloudbuild.googleapis.com`)
        *   Artifact Registry API (`artifactregistry.googleapis.com`)
        *   Cloud Run API (`run.googleapis.com`)
        *   IAM API (`iam.googleapis.com`)
        *   Compute Engine API (`compute.googleapis.com`) (often needed by dependent services)
    *   Ensure your user account or the service account used by Cloud Build has necessary permissions (e.g., Cloud Build Editor, Artifact Registry Writer, Cloud Run Admin, Service Account User).

## Setup

1.  **Clone the repository (if applicable)**

2.  **Configure Environment Variables**:
    *   Copy the example environment file: `cp .env.example .env`
    *   Edit the `.env` file and fill in your specific values:
        *   `HF_TOKEN`: Your Hugging Face read token.
        *   `PROJECT_ID`: Your Google Cloud Project ID.
        *   `REGION`: The GCP region where you want to deploy (e.g., `us-central1`).
        *   (Optional) `SERVICE_NAME`, `IMAGE_NAME`: Change if desired.

3.  **Check Configuration**:
    *   Run `make init`.
    *   This command verifies that the `.env` file exists and contains the required variables (`HF_TOKEN`, `PROJECT_ID`, `REGION`).

## Build

1.  **Build the Docker Image via Cloud Build**:
    *   Run `make build`.
    *   This command uses `gcloud builds submit` to:
        *   Send the project context to Cloud Build.
        *   Build the Docker image according to the `Dockerfile`.
        *   Securely pass your `HF_TOKEN` as a build argument to download the Gemma model adapter during the build.
        *   Tag the image and push it to your project's Artifact Registry.
    *   **Note**: The first build might take a significant amount of time (15-45 minutes) depending on the machine type used by Cloud Build and the model download speed.

## Deploy

1.  **Deploy the Image to Cloud Run**:
    *   Run `make deploy`.
    *   This command uses `gcloud run deploy` to:
        *   Create or update a Cloud Run service.
        *   Use the image built in the previous step.
        *   Configure settings like memory (8Gi), CPU (2), port (8080), timeout, and allow unauthenticated access for testing.
    *   The deployment process will output a **Service URL** once complete.

## Usage

Once deployed, you can interact with the RAG agent endpoint:

1.  **Find the Service URL**: Get it from the `make deploy` output or using `gcloud run services describe SERVICE_NAME --region=REGION --format='value(status.url)'` (replace `SERVICE_NAME` and `REGION` with your values).

2.  **Send a POST Request**: Use `curl` or any HTTP client to send a POST request to the `/invoke` endpoint of your service URL.

   ```bash
   SERVICE_URL="YOUR_CLOUD_RUN_SERVICE_URL"
   curl -X POST "${SERVICE_URL}/invoke" \
     -H "Content-Type: application/json" \
     -d '{
       "question": "What are the main components of an AI agent?"
     }'
   ```

3.  **Check Health**: You can check the service health at the `/health` endpoint:
   ```bash
   curl "${SERVICE_URL}/health"
   ```

## Makefile Targets

*   `make init`: Check environment configuration.
*   `make build`: Build the Docker image using Cloud Build.
*   `make deploy`: Deploy the image to Cloud Run.
*   `make clean`: Remove local Python cache files.
*   `make help` or `make`: Show available commands.
