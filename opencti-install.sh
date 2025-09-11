#!/bin/bash

# OpenCTI Installation Script for Ubuntu
# This script installs Docker, Docker Compose, and deploys OpenCTI

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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
   error "This script should not be run as root. Please run as a regular user with sudo privileges."
   exit 1
fi

# Check Ubuntu version
check_ubuntu_version() {
    if ! command -v lsb_release &> /dev/null; then
        error "lsb_release not found. This script requires Ubuntu."
        exit 1
    fi
    
    UBUNTU_VERSION=$(lsb_release -rs)
    log "Detected Ubuntu version: $UBUNTU_VERSION"
    
    if [[ ! "$UBUNTU_VERSION" =~ ^(20\.04|22\.04|23\.04|23\.10|24\.04)$ ]]; then
        warning "This script is tested on Ubuntu 20.04, 22.04, 23.04, 23.10, and 24.04. You're running $UBUNTU_VERSION."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Generate random passwords
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-20
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# Update system packages
update_system() {
    log "Updating system packages..."
    sudo apt update
    sudo apt upgrade -y
    success "System updated successfully"
}

# Install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."
    sudo apt install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        openssl \
        git \
        jq \
        wget
    success "Prerequisites installed successfully"
}

# Install Docker
install_docker() {
    log "Installing Docker..."
    
    # Remove old versions
    sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    success "Docker installed successfully"
}

# Verify Docker installation
verify_docker() {
    log "Verifying Docker installation..."
    if ! docker --version; then
        error "Docker installation failed"
        exit 1
    fi
    success "Docker is working correctly"
}

# Install Docker Compose (legacy method as fallback)
install_docker_compose() {
    log "Installing Docker Compose..."
    
    # Try to use docker compose plugin first
    if docker compose version &>/dev/null; then
        success "Docker Compose is already available"
        return
    fi
    
    # Install legacy docker-compose
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    if ! docker-compose --version; then
        error "Docker Compose installation failed"
        exit 1
    fi
    
    success "Docker Compose installed successfully"
}

# Fix Docker permissions
fix_docker_permissions() {
    log "Fixing Docker permissions..."
    
    # Add user to docker group if not already
    if ! groups $USER | grep -q docker; then
        sudo usermod -aG docker $USER
        log "User added to docker group. You may need to log out and back in for changes to take effect."
    fi
    
    # Restart Docker service
    sudo systemctl restart docker
    
    success "Docker permissions fixed"
}

# Create OpenCTI directory and files
setup_opencti() {
    log "Setting up OpenCTI deployment..."
    
    # Create project directory
    mkdir -p ~/opencti-deployment
    cd ~/opencti-deployment
    
    # Generate secure passwords and tokens
    MINIO_ROOT_USER="minioadmin"
    MINIO_ROOT_PASSWORD=$(generate_password)
    RABBITMQ_DEFAULT_USER="rabbitmquser"
    RABBITMQ_DEFAULT_PASS=$(generate_password)
    OPENCTI_ADMIN_EMAIL="admin@opencti.local"
    OPENCTI_ADMIN_PASSWORD=$(generate_password)
    OPENCTI_ADMIN_TOKEN=$(generate_password)
    OPENCTI_SESSION_SECRET=$(generate_password)
    CONNECTOR_EXPORT_FILE_STIX_ID=$(generate_uuid)
    
    # Create .env file
    cat > .env << EOF
# MinIO Configuration
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}

# RabbitMQ Configuration
RABBITMQ_DEFAULT_USER=${RABBITMQ_DEFAULT_USER}
RABBITMQ_DEFAULT_PASS=${RABBITMQ_DEFAULT_PASS}

# OpenCTI Admin Configuration
OPENCTI_ADMIN_EMAIL=${OPENCTI_ADMIN_EMAIL}
OPENCTI_ADMIN_PASSWORD=${OPENCTI_ADMIN_PASSWORD}
OPENCTI_ADMIN_TOKEN=${OPENCTI_ADMIN_TOKEN}
OPENCTI_SESSION_SECRET=${OPENCTI_SESSION_SECRET}

# SMTP Configuration (optional)
SMTP_HOSTNAME=localhost

# Connector IDs
CONNECTOR_EXPORT_FILE_STIX_ID=${CONNECTOR_EXPORT_FILE_STIX_ID}
EOF

    # Create docker-compose.yml (without version attribute)
    cat > docker-compose.yml << 'EOF'
services:
  # Redis for caching
  redis:
    image: redis:7.0
    restart: unless-stopped
    volumes:
      - redis_data:/data

  # Elasticsearch for indexing
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.3
    restart: unless-stopped
    volumes:
      - es_data:/usr/share/elasticsearch/data
    environment:
      - discovery.type=single-node
      - xpack.ml.enabled=false
      - logger.level=ERROR
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    mem_limit: 4g

  # MinIO for file storage
  minio:
    image: minio/minio:RELEASE.2023-11-01T18-37-25Z
    restart: unless-stopped
    volumes:
      - s3_data:/data
    ports:
      - "9000:9000"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    command: server /data

  # RabbitMQ for message queuing
  rabbitmq:
    image: rabbitmq:3.12-management
    restart: unless-stopped
    environment:
      - RABBITMQ_DEFAULT_USER=${RABBITMQ_DEFAULT_USER}
      - RABBITMQ_DEFAULT_PASS=${RABBITMQ_DEFAULT_PASS}
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq

  # OpenCTI Platform
  opencti:
    image: opencti/platform:5.12.15
    restart: unless-stopped
    depends_on:
      - redis
      - elasticsearch
      - minio
      - rabbitmq
    ports:
      - "8080:8080"
    environment:
      - APP__PORT=8080
      - APP__ADMIN__EMAIL=${OPENCTI_ADMIN_EMAIL}
      - APP__ADMIN__PASSWORD=${OPENCTI_ADMIN_PASSWORD}
      - APP__ADMIN__TOKEN=${OPENCTI_ADMIN_TOKEN}
      - APP__SESSION_TIMEOUT=28800000
      - APP__SESSION_SECRET=${OPENCTI_SESSION_SECRET}
      - REDIS__HOSTNAME=redis
      - REDIS__PORT=6379
      - ELASTICSEARCH__URL=http://elasticsearch:9200
      - MINIO__ENDPOINT=minio
      - MINIO__PORT=9000
      - MINIO__USE_SSL=false
      - MINIO__ACCESS_KEY=${MINIO_ROOT_USER}
      - MINIO__SECRET_KEY=${MINIO_ROOT_PASSWORD}
      - RABBITMQ__HOSTNAME=rabbitmq
      - RABBITMQ__PORT=5672
      - RABBITMQ__PORT_MANAGEMENT=15672
      - RABBITMQ__MANAGEMENT_SSL=false
      - RABBITMQ__USERNAME=${RABBITMQ_DEFAULT_USER}
      - RABBITMQ__PASSWORD=${RABBITMQ_DEFAULT_PASS}
      - SMTP__HOSTNAME=${SMTP_HOSTNAME}
      - SMTP__PORT=25
      - PROVIDERS__LOCAL__STRATEGY=LocalStrategy

  # OpenCTI Workers
  worker:
    image: opencti/worker:5.12.15
    restart: unless-stopped
    depends_on:
      - opencti
    environment:
      - OPENCTI_URL=http://opencti:8080
      - OPENCTI_TOKEN=${OPENCTI_ADMIN_TOKEN}
      - WORKER_LOG_LEVEL=info
      - REDIS__HOSTNAME=redis
      - REDIS__PORT=6379

  # Export File STIX Connector
  connector-export-file-stix:
    image: opencti/connector-export-file-stix:5.12.15
    restart: unless-stopped
    depends_on:
      - opencti
    environment:
      - OPENCTI_URL=http://opencti:8080
      - OPENCTI_TOKEN=${OPENCTI_ADMIN_TOKEN}
      - CONNECTOR_ID=${CONNECTOR_EXPORT_FILE_STIX_ID}
      - CONNECTOR_TYPE=INTERNAL_EXPORT_FILE
      - CONNECTOR_NAME=ExportFileStix2
      - CONNECTOR_SCOPE=application/json
      - CONNECTOR_CONFIDENCE_LEVEL=100
      - CONNECTOR_LOG_LEVEL=info

volumes:
  es_data:
  redis_data:
  s3_data:
  rabbitmq_data:
EOF

    success "OpenCTI setup completed"
}

# Start OpenCTI services
start_opencti() {
    log "Starting OpenCTI services..."
    
    cd ~/opencti-deployment
    
    # Pull images
    if command -v docker-compose &> /dev/null; then
        docker-compose pull
        docker-compose up -d
    else
        docker compose pull
        docker compose up -d
    fi
    
    success "OpenCTI services started"
}

# Wait for OpenCTI to be ready
wait_for_opencti() {
    log "Waiting for OpenCTI to be ready (this may take 5-10 minutes)..."
    
    # Wait for OpenCTI service to be healthy
    for i in {1..60}; do
        if command -v docker-compose &> /dev/null; then
            if docker-compose ps | grep -q "opencti.*Up"; then
                log "OpenCTI container is running"
                break
            fi
        else
            if docker compose ps | grep -q "opencti.*Up"; then
                log "OpenCTI container is running"
                break
            fi
        fi
        log "Waiting for containers to start... ($i/60)"
        sleep 10
    done
    
    # Check if services are responding
    for i in {1..30}; do
        if curl -s http://localhost:8080 | grep -q "OpenCTI"; then
            success "OpenCTI is ready!"
            return 0
        fi
        log "Waiting for OpenCTI web interface... ($i/30)"
        sleep 10
    done
    
    warning "OpenCTI might still be initializing. Check logs with: docker compose logs -f"
}

# Display connection information
show_connection_info() {
    cd ~/opencti-deployment
    
    log "OpenCTI Installation Complete!"
    echo
    echo "=================== CONNECTION DETAILS ==================="
    echo "Web Interface: http://$(hostname -I | awk '{print $1}'):8080"
    echo "Admin Email: $(grep OPENCTI_ADMIN_EMAIL .env | cut -d'=' -f2)"
    echo "Admin Password: $(grep OPENCTI_ADMIN_PASSWORD .env | cut -d'=' -f2)"
    echo "========================================================="
    echo
    echo "=================== SERVICE PASSWORDS ==================="
    echo "MinIO Credentials:"
    echo "  Username: $(grep MINIO_ROOT_USER .env | cut -d'=' -f2)"
    echo "  Password: $(grep MINIO_ROOT_PASSWORD .env | cut -d'=' -f2)"
    echo
    echo "RabbitMQ Credentials:"
    echo "  Username: $(grep RABBITMQ_DEFAULT_USER .env | cut -d'=' -f2)"
    echo "  Password: $(grep RABBITMQ_DEFAULT_PASS .env | cut -d'=' -f2)"
    echo "========================================================="
    echo
    echo "IMPORTANT: Save these credentials in a secure location!"
    echo "The passwords are only stored in ~/opencti-deployment/.env"
    echo
    echo "=================== USEFUL COMMANDS ===================="
    echo "Check status: docker compose ps"
    echo "View logs: docker compose logs -f"
    echo "Stop services: docker compose down"
    echo "Start services: docker compose up -d"
    echo "========================================================"
    echo
}

# Create management script
create_management_script() {
    cat > ~/opencti-manage.sh << 'EOF'
#!/bin/bash

# OpenCTI Management Script
cd ~/opencti-deployment

# Determine which docker compose command to use
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    echo "Error: Docker Compose not found"
    exit 1
fi

case "$1" in
    start)
        echo "Starting OpenCTI..."
        $DOCKER_COMPOSE up -d
        ;;
    stop)
        echo "Stopping OpenCTI..."
        $DOCKER_COMPOSE down
        ;;
    restart)
        echo "Restarting OpenCTI..."
        $DOCKER_COMPOSE down
        $DOCKER_COMPOSE up -d
        ;;
    logs)
        $DOCKER_COMPOSE logs -f
        ;;
    status)
        $DOCKER_COMPOSE ps
        ;;
    update)
        echo "Updating OpenCTI..."
        $DOCKER_COMPOSE down
        $DOCKER_COMPOSE pull
        $DOCKER_COMPOSE up -d
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|logs|status|update}"
        exit 1
        ;;
esac
EOF

    chmod +x ~/opencti-manage.sh
    success "Management script created at ~/opencti-manage.sh"
}

# Main installation function
main() {
    log "Starting OpenCTI installation on Ubuntu..."
    
    check_ubuntu_version
    update_system
    install_prerequisites
    install_docker
    verify_docker
    install_docker_compose
    fix_docker_permissions
    setup_opencti
    start_opencti
    wait_for_opencti
    create_management_script
    show_connection_info
    
    success "OpenCTI installation completed successfully!"
    log "Please save your credentials and consider securing your installation with HTTPS"
    log "You may need to log out and back in for Docker permissions to take effect"
}

# Run main function
main "$@"
