#!/bin/bash
cd "$PROJECT_DIR"

# Load environment variables from .env file if it exists
if [[ -f ".env" ]]; then
  export $(grep -v '^#' .env | xargs)
fi

docker compose up -d
