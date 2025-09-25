#!/bin/bash

# Simplified container management script
set -euo pipefail

# Script directory and load .env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try to load .env from current directory first, then parent
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    source "${SCRIPT_DIR}/.env"
elif [[ -f "${SCRIPT_DIR}/../.env" ]]; then
    source "${SCRIPT_DIR}/../.env"
else
    echo "❌ .env file not found!"
    echo "💡 Create a .env file with required variables (APP_NAME, REGISTRY, BASE_IMAGE, etc.)"
    exit 1
fi

# Default values
APP_NAME="${APP_NAME:-eligibility-mcp}"
VERSION="${VERSION:-$(git rev-parse --short HEAD 2>/dev/null || echo 'latest')}"
IMAGE_TAG="${REGISTRY}/${APP_NAME}:${VERSION}"
LATEST_TAG="${REGISTRY}/${APP_NAME}:latest"
CONTAINERFILE="${CONTAINERFILE:-Containerfile}"

# Container runtime detection
if command -v podman &> /dev/null; then
    RUNTIME="podman"
elif command -v docker &> /dev/null; then
    RUNTIME="docker"
else
    echo "❌ Neither podman nor docker found!"
    exit 1
fi

# Build the container image
build() {
    echo "🔨 Building ${IMAGE_TAG}..."
    
    # Handle vLLM repository cloning/updating
    local vllm_dir="${SCRIPT_DIR}/vllm"
    if [[ -d "${vllm_dir}" ]]; then
        echo "📥 Updating existing vLLM repository..."
        (cd "${vllm_dir}" && git pull)
    else
        echo "📦 Cloning vLLM repository..."
        git clone https://github.com/vllm-project/vllm.git "${vllm_dir}"
    fi
    echo "✅ vLLM repository ready"
    
    local build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local vcs_ref=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    
    ${RUNTIME} build \
        --file "${CONTAINERFILE}" \
        --tag "${IMAGE_TAG}" \
        --tag "${LATEST_TAG}" \
        --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
        --build-arg "BASE_TAG=${BASE_TAG}" \
        --build-arg "VERSION=${VERSION}" \
        --build-arg "BUILD_DATE=${build_date}" \
        --build-arg "VCS_REF=${vcs_ref}" \
        --build-arg "MAINTAINER=${MAINTAINER}" \
        --build-arg "DESCRIPTION=${DESCRIPTION}" \
        ${CACHE_FLAG:-} \
        .
    
    echo "✅ Build completed: ${IMAGE_TAG}"
}

# Push the container image
push() {
    echo "📤 Pushing ${IMAGE_TAG}..."
    ${RUNTIME} push "${IMAGE_TAG}"
    ${RUNTIME} push "${LATEST_TAG}"
    echo "✅ Push completed"
}

# Run the container locally
run() {
    echo "🚀 Running ${IMAGE_TAG}..."
    local container_name="${APP_NAME}-local"
    
    # Stop existing container if it exists
    ${RUNTIME} stop "${container_name}" 2>/dev/null || true
    ${RUNTIME} rm "${container_name}" 2>/dev/null || true
    
    ${RUNTIME} run \
        --name "${container_name}" \
        --rm \
        -it \
        -p "${PORT:-8000}:${PORT:-8000}" \
        "${IMAGE_TAG}"
}

# Clean up images and containers
clean() {
    echo "🧹 Cleaning up..."
    
    # Remove containers
    ${RUNTIME} ps -a --filter "name=${APP_NAME}" --format "{{.Names}}" | xargs ${RUNTIME} rm -f 2>/dev/null || true
    
    # Remove images
    ${RUNTIME} images --filter "reference=${REGISTRY}/${APP_NAME}" --format "{{.Repository}}:{{.Tag}}" | xargs ${RUNTIME} rmi -f 2>/dev/null || true
    
    echo "✅ Cleanup completed"
}

# Show image information
info() {
    echo "📋 Container Information"
    echo "App: ${APP_NAME}"
    echo "Version: ${VERSION}"
    echo "Image: ${IMAGE_TAG}"
    echo "Registry: ${REGISTRY}"
    echo "Runtime: ${RUNTIME}"
    
    echo -e "\n📦 Available Images:"
    ${RUNTIME} images --filter "reference=${REGISTRY}/${APP_NAME}" || echo "No images found"
    
    echo -e "\n🏃 Running Containers:"
    ${RUNTIME} ps --filter "name=${APP_NAME}" || echo "No running containers"
}

# Show usage
usage() {
    echo "Usage: $0 {build|push|run|clean|info}"
    echo ""
    echo "Commands:"
    echo "  build  - Build container image"
    echo "  push   - Push to registry"
    echo "  run    - Run locally"
    echo "  clean  - Remove containers and images"
    echo "  info   - Show container information"
    echo ""
    echo "Configuration loaded from .env file"
}

# Main logic
case "${1:-}" in
    build) build ;;
    push) push ;;
    run) run ;;
    clean) clean ;;
    info) info ;;
    help|--help|-h) usage ;;
    *)
        echo "❌ Unknown command: ${1:-}"
        usage
        exit 1
        ;;
esac