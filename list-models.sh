#!/bin/bash

# Get authentication token
TOKEN=$(gcloud auth print-identity-token)

# Set default URL or use provided URL
URL=${1:-"https://YOUR_SERVICE_NAME.YOUR_REGION.run.app"}
ENDPOINT="/api/tags"

echo "Listing available models from $URL$ENDPOINT"
echo "-----------------------------------"

# Make the request to list models
curl -s -X GET \
  -H "Authorization: Bearer $TOKEN" \
  "$URL$ENDPOINT" | jq .

echo "-----------------------------------"
