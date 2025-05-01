#!/bin/bash

# Get authentication token if needed
if [[ "$1" == "--auth" ]]; then
  TOKEN=$(gcloud auth print-identity-token)
  echo "Using authentication token: $TOKEN"
  shift
else
  TOKEN=""
fi

# Set default values
MODEL=${1:-"gemma3:4b"}
PROMPT=${2:-"Write a poem about Gemma3"}
URL=${3:-"https://YOUR_SERVICE_NAME.YOUR_REGION.run.app"}
API_TYPE=${4:-"generate"} # Can be: generate, chat, openai

# Set the appropriate endpoint based on API type
case "$API_TYPE" in
  "generate")
    ENDPOINT="/api/generate"
    PAYLOAD="{\"model\": \"$MODEL\", \"prompt\": \"$PROMPT\"}"
    ;;
  "chat")
    ENDPOINT="/api/chat"
    PAYLOAD="{\"model\": \"$MODEL\", \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}]}"
    ;;
  "openai")
    ENDPOINT="/v1/chat/completions"
    PAYLOAD="{\"model\": \"$MODEL\", \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}]}"
    ;;
  *)
    echo "Error: Unknown API type '$API_TYPE'. Must be one of: generate, chat, openai"
    exit 1
    ;;
esac

echo "Sending request to $URL$ENDPOINT"
echo "API type: $API_TYPE"
echo "Model: $MODEL"
echo "Prompt: $PROMPT"
echo "-----------------------------------"

# Function to parse JSON and extract the response field based on API type
parse_response() {
  local json="$1"
  local api_type="$2"
  
  case "$api_type" in
    "generate")
      # Extract the 'response' field from /api/generate
      echo "$json" | grep -o '"response":"[^"]*"' | cut -d'"' -f4
      ;;
    "chat")
      # Extract the 'message.content' field from /api/chat
      echo "$json" | grep -o '"content":"[^"]*"' | cut -d'"' -f4
      ;;
    "openai")
      # Extract the 'choices[0].message.content' field from /v1/chat/completions
      echo "$json" | grep -o '"content":"[^"]*"' | cut -d'"' -f4
      ;;
  esac
}

# Use curl to make the request and process the streaming response
if [[ -n "$TOKEN" ]]; then
  # With authentication
  curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$URL$ENDPOINT" | while read -r line; do
      if [[ -n "$line" ]]; then
        response=$(parse_response "$line" "$API_TYPE")
        if [[ -n "$response" ]]; then
          printf "%s" "$response"
        else
          # If no response field found, print the raw JSON for debugging
          echo "DEBUG: $line" >&2
        fi
      fi
    done
else
  # Without authentication
  curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$URL$ENDPOINT" | while read -r line; do
      if [[ -n "$line" ]]; then
        response=$(parse_response "$line" "$API_TYPE")
        if [[ -n "$response" ]]; then
          printf "%s" "$response"
        else
          # If no response field found, print the raw JSON for debugging
          echo "DEBUG: $line" >&2
        fi
      fi
    done
fi

echo -e "\n-----------------------------------"
echo "Request completed"
