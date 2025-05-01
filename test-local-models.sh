#!/bin/bash

# Script to test the local Ollama API

# Get model name from command line or use default
MODEL=${1:-"gemma3:27b-it-qat"}
PROMPT=${2:-"Hello, world!"}
URL=${3:-"http://localhost:8080"}

echo "Testing local Ollama API at $URL"
echo "Using model: $MODEL"
echo "Prompt: $PROMPT"

echo -e "\nChecking available models..."
curl -s $URL/api/tags | jq .

echo -e "\nTesting Ollama completion API..."
curl -s -X POST $URL/api/generate \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"prompt\": \"$PROMPT\"
  }" | jq .

echo -e "\nTesting Ollama chat API..."
curl -s -X POST $URL/api/chat \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}]
  }" | jq .

echo -e "\nTesting Ollama completions API (OpenAI compatible)..."
curl -s -X POST $URL/v1/completions \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"prompt\": \"$PROMPT\",
    \"max_tokens\": 100
  }" | jq .

echo -e "\nTesting Ollama chat completions API (OpenAI compatible)..."
curl -s -X POST $URL/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}]
  }" | jq .
