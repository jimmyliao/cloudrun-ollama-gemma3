### reference
https://cloud.google.com/run/docs/tutorials/gpu-gemma-with-ollama

### environment
(project_id: gde-kj)
(repository: ollama-gemma3)

### Commands

1. 
    ```bash
    gcloud config set project gde-kj
    ```

2. 
    ```bash
    gcloud config set run/region us-central1
    ```

3.
    ```bash
    gcloud artifacts repositories create ollama-gemma3 \
      --repository-format=docker \
      --location=us-central1
    ```

4. 
    ```bash
    gcloud builds submit \
      --tag us-central1-docker.pkg.dev/gde-kj/ollama-gemma3/ollama-gemma \
      --machine-type e2-highcpu-32
    ```

5. 
    ```bash
    gcloud run deploy ollama-gemma \
      --image us-central1-docker.pkg.dev/gde-kj/ollama-gemma3/ollama-gemma \
      --concurrency 4 \
      --cpu 8 \
      --set-env-vars OLLAMA_NUM_PARALLEL=4 \
      --gpu 1 \
      --gpu-type nvidia-l4 \
      --max-instances 1 \
      --memory 32Gi \
      --no-allow-unauthenticated \
      --no-cpu-throttling \
      --timeout=120
    ```