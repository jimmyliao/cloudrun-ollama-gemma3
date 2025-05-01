#!/bin/bash

# Script to check available Gemma models in Ollama's library

echo "Checking available Gemma models in Ollama's library..."
echo "-----------------------------------"

# Use curl to fetch the Ollama library page and extract Gemma model names
curl -s https://ollama.com/library | grep -o 'href="/library/[^"]*gemma[^"]*"' | sed 's|href="/library/||g' | sed 's/"//g' | sort

echo "-----------------------------------"
echo "Note: These are the model names as listed in Ollama's library."
echo "Use these exact names in your MODEL_NAME parameter."
