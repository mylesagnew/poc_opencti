A complete Docker Compose deployment for OpenCTI (Open Cyber Threat Intelligence) Platform with all required services.

📋 Table of Contents
Overview
Prerequisites
Installation
Quick Start
Configuration
Usage
Services
Management
Security
Troubleshooting
Updates
Backup & Restore
📖 Overview
This repository provides a production-ready Docker Compose configuration for deploying OpenCTI with all its dependencies:

OpenCTI Platform
Elasticsearch (indexing)
Redis (caching)
MinIO (file storage)
RabbitMQ (message queuing)
Worker processes
Essential connectors
⚙️ Prerequisites
System Requirements
OS: Ubuntu 20.04/22.04 LTS (recommended) or any Linux distribution
RAM: Minimum 8GB (16GB recommended)
Disk Space: 20GB free space (50GB+ recommended for production)
CPU: 2+ cores
Network: Internet access for Docker image downloads
Required Software
Docker Engine 20.10+
Docker Compose 1.29+ or Docker Compose Plugin
