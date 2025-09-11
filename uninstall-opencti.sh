#!/bin/bash
# OpenCTI Uninstallation Script for Ubuntu
# This script stops and removes OpenCTI Docker containers, volumes, and project files.

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Please run as a regular user with sudo privileges if needed for Docker commands."
   # Note: Docker commands might need sudo depending on setup, but the script itself doesn't require root.
fi

# Determine Docker Compose command
DOCKER_COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    warning "Docker Compose command not found. Assuming services are not running or were removed."
fi

# Default project directory
PROJECT_DIR="$HOME/opencti-deployment"

# Function to stop and remove containers and volumes
remove_containers_and_volumes() {
    if [[ -n "$DOCKER_COMPOSE_CMD" ]] && [[ -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        log "Navigating to project directory: $PROJECT_DIR"
        cd "$PROJECT_DIR" || { error "Failed to navigate to $PROJECT_DIR"; exit 1; }

        log "Stopping OpenCTI services..."
        # Use || true to prevent script exit if 'down' fails (e.g., if already down)
        $DOCKER_COMPOSE_CMD down --volumes --remove-orphans || true

        success "OpenCTI services stopped and volumes removed (if they existed)."
    else
        warning "Docker Compose command not found or docker-compose.yml missing in $PROJECT_DIR. Skipping container/volume removal via Compose."
        # Fallback: Try to remove containers/volumes by name/pattern if Compose fails or isn't available
        log "Attempting to remove containers and volumes by name/pattern..."
        # Stop and remove containers
        docker ps -aq --filter "name=opencti" | xargs -r docker stop 2>/dev/null || true
        docker ps -aq --filter "name=opencti" | xargs -r docker rm -v 2>/dev/null || true
        # Remove volumes associated with the project (named volumes)
        docker volume ls -q --filter "name=opencti" | xargs -r docker volume rm 2>/dev/null || true
        success "Finished attempting removal by name/pattern."
    fi
}

# Function to remove the project directory
remove_project_directory() {
    if [[ -d "$PROJECT_DIR" ]]; then
        log "Removing project directory: $PROJECT_DIR"
        rm -rf "$PROJECT_DIR"
        success "Project directory removed."
    else
        warning "Project directory $PROJECT_DIR not found. Skipping removal."
    fi
}

# Function to remove downloaded Docker images (optional)
remove_docker_images() {
    read -p "Do you want to remove the Docker images downloaded by the installer? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Removing Docker images used by the OpenCTI deployment..."
        # List of images used in the installer's docker-compose.yml
        IMAGES_TO_REMOVE=(
            "redis:7.0"
            "docker.elastic.co/elasticsearch/elasticsearch:8.11.3"
            "minio/minio:RELEASE.2023-11-01T18-37-25Z"
            "rabbitmq:3.12-management"
            "opencti/platform:5.12.15"
            "opencti/worker:5.12.15"
            "opencti/connector-export-file-stix:5.12.15"
        )

        for image in "${IMAGES_TO_REMOVE[@]}"; do
             if docker image inspect "$image" &>/dev/null; then
                 log "Removing image: $image"
                 docker rmi "$image" || warning "Failed to remove image $image"
             else
                 log "Image not found locally, skipping: $image"
             fi
        done
        success "Finished removing Docker images (attempted)."
    else
        log "Skipping Docker image removal."
    fi
}

# Function to remove management script
remove_management_script() {
    MANAGEMENT_SCRIPT="$HOME/opencti-manage.sh"
    if [[ -f "$MANAGEMENT_SCRIPT" ]]; then
        log "Removing management script: $MANAGEMENT_SCRIPT"
        rm -f "$MANAGEMENT_SCRIPT"
        success "Management script removed."
    else
        warning "Management script $MANAGEMENT_SCRIPT not found. Skipping removal."
    fi
}

# Main uninstallation function
main() {
    log "Starting OpenCTI uninstallation..."

    remove_containers_and_volumes
    remove_project_directory
    remove_management_script
    remove_docker_images # Optional step

    success "OpenCTI uninstallation process completed!"
    log "Note: System configurations (like vm.max_map_count, ulimits) made by the installer are not reverted by this script."
    log "Docker and Docker Compose installations are also not removed."
}

# Run main function
main "$@"
