#!/bin/bash

set -euo pipefail

# Logging setup
LOG_FILE="deploy_$(date +%Y%m%d).log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

err() {
  log "ERROR: $*" >&2
  exit 1
}

trap 'err "Unexpected error at line $LINENO"' ERR

# Handle --cleanup flag
if [ "${1:-}" = "--cleanup" ]; then
  log "Starting cleanup..."
  # Collect minimal inputs for cleanup
  read -p "Enter Git Repository URL (for repo name): " GIT_URL
  REPO_NAME=$(basename "$GIT_URL" .git)
  read -p "Enter SSH Username: " SSH_USER
  read -p "Enter Server IP Address: " SERVER_IP
  read -p "Enter SSH Key Path: " SSH_KEY
  if [ ! -f "$SSH_KEY" ]; then err "SSH key not found"; fi

  ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" <<EOF
set -euo pipefail
APP_NAME="$REPO_NAME"
PROJ_DIR="/home/$SSH_USER/$REPO_NAME"
if [ -d "\$PROJ_DIR" ]; then
  cd "\$PROJ_DIR"
  if [ -f "docker-compose.yml" ]; then
    docker-compose down -v || true
  else
    docker stop \$APP_NAME || true
    docker rm \$APP_NAME || true
    docker rmi \$APP_NAME || true
  fi
fi
rm -rf "\$PROJ_DIR"
sudo rm -f /etc/nginx/sites-available/\$APP_NAME /etc/nginx/sites-enabled/\$APP_NAME
sudo nginx -t && sudo systemctl reload nginx || echo "Nginx reload failed during cleanup"
EOF
  log "Cleanup completed"
  exit 0
fi

# 1. Collect Parameters
log "Collecting user inputs..."
read -p "Enter Git Repository URL: " GIT_URL
if [[ ! "$GIT_URL" =~ ^https:// ]]; then err "Invalid Git URL"; fi

read -s -p "Enter Personal Access Token (PAT): " PAT
echo

read -p "Enter Branch name (default: main): " BRANCH
BRANCH=${BRANCH:-main}

read -p "Enter SSH Username: " SSH_USER

read -p "Enter Server IP Address: " SERVER_IP
if ! [[ $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then err "Invalid IP address"; fi

read -p "Enter SSH Key Path: " SSH_KEY
if [ ! -f "$SSH_KEY" ]; then err "SSH key not found"; fi

read -p "Enter Application Port (internal container port): " APP_PORT
if ! [[ $APP_PORT =~ ^[0-9]+$ ]] || [ "$APP_PORT" -lt 1 ] || [ "$APP_PORT" -gt 65535 ]; then err "Invalid port"; fi
if [ "$APP_PORT" -eq 80 ] || [ "$APP_PORT" -eq 443 ]; then err "Port cannot be 80 or 443 to avoid conflicts"; fi

REPO_NAME=$(basename "$GIT_URL" .git)

# 2. Clone the Repository
log "Cloning or updating repository $REPO_NAME..."
if [ -d "$REPO_NAME" ]; then
  cd "$REPO_NAME"
  git pull origin "$BRANCH" || err "Git pull failed"
  git checkout "$BRANCH" || err "Git checkout failed"
  cd ..
else
  CLONE_URL=$(echo "$GIT_URL" | sed "s|https://|https://${PAT}@|")
  git clone "$CLONE_URL" || err "Git clone failed"
  cd "$REPO_NAME"
  git checkout "$BRANCH" || err "Git checkout failed"
  cd ..
fi

# 3. Navigate into Cloned Directory and Verify Dockerfile
cd "$REPO_NAME" || err "Failed to enter repository directory"
if [ ! -f "Dockerfile" ] && [ ! -f "docker-compose.yml" ]; then
  err "Neither Dockerfile nor docker-compose.yml found"
fi
USE_COMPOSE=0
if [ -f "docker-compose.yml" ]; then
  USE_COMPOSE=1
  log "docker-compose.yml detected; will use Docker Compose"
else
  log "Dockerfile detected; will use basic Docker build/run"
fi
cd ..

# 4. SSH Connectivity Check
log "Checking SSH connectivity to $SSH_USER@$SERVER_IP..."
ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 "$SSH_USER@$SERVER_IP" 'echo "SSH connection successful"' || err "SSH connectivity check failed"

# 5. Prepare Remote Environment
log "Preparing remote environment..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" <<EOF || err "Remote preparation failed"
set -euo pipefail
remote_log() { echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$*" | tee -a /tmp/deploy.log; }
remote_err() { remote_log "ERROR: \$*" >&2; exit 1; }
trap 'remote_err "Unexpected error"' ERR

remote_log "Updating system packages..."
sudo apt update -y && sudo apt upgrade -y

if ! command -v docker &> /dev/null; then
  remote_log "Installing Docker..."
  sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update -y
  sudo apt install -y docker-ce docker-ce-cli containerd.io
fi

if ! command -v docker-compose &> /dev/null; then
  remote_log "Installing Docker Compose..."
  sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
fi

if ! command -v nginx &> /dev/null; then
  remote_log "Installing Nginx..."
  sudo apt install -y nginx
fi

sudo usermod -aG docker \$USER || true
sudo systemctl enable docker --now
sudo systemctl enable nginx --now

remote_log "Docker version: \$(docker --version)"
remote_log "Docker Compose version: \$(docker-compose --version)"
remote_log "Nginx version: \$(nginx -v 2>&1)"
EOF

# 6. Deploy the Dockerized Application
log "Transferring project files to remote..."
rsync -avz --delete -e "ssh -i $SSH_KEY" "$REPO_NAME/" "$SSH_USER@$SERVER_IP:/home/$SSH_USER/$REPO_NAME/" || err "File transfer failed"

log "Deploying application on remote..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" <<EOF || err "Deployment failed"
set -euo pipefail
remote_log() { echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$*" | tee -a /tmp/deploy.log; }
remote_err() { remote_log "ERROR: \$*" >&2; exit 1; }
trap 'remote_err "Unexpected error"' ERR

cd /home/$SSH_USER/$REPO_NAME
APP_NAME="$REPO_NAME"

if [ $USE_COMPOSE -eq 1 ]; then
  remote_log "Stopping existing containers..."
  docker-compose down || true
  remote_log "Building and starting with Docker Compose..."
  docker-compose build || remote_err "Build failed"
  docker-compose up -d || remote_err "Up failed"
else
  remote_log "Stopping and removing existing container..."
  docker stop \$APP_NAME || true
  docker rm \$APP_NAME || true
  docker rmi \$APP_NAME || true
  remote_log "Building and running Docker container..."
  docker build -t \$APP_NAME . || remote_err "Build failed"
  docker run -d --name \$APP_NAME -p 127.0.0.1:$APP_PORT:$APP_PORT \$APP_NAME || remote_err "Run failed"
fi

sleep 10  # Wait for container to start
if [ $USE_COMPOSE -eq 1 ]; then
  if [ \$(docker-compose ps -q | wc -l) -eq 0 ]; then
    docker-compose logs
    remote_err "Containers not healthy"
  fi
else
  if ! docker ps | grep -q \$APP_NAME; then
    docker logs \$APP_NAME
    remote_err "Container not healthy"
  fi
fi
remote_log "Application deployed and accessible on port $APP_PORT"
EOF

# 7. Configure Nginx as Reverse Proxy
log "Configuring Nginx on remote..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" <<EOF || err "Nginx configuration failed"
set -euo pipefail
remote_log() { echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$*" | tee -a /tmp/deploy.log; }
remote_err() { remote_log "ERROR: \$*" >&2; exit 1; }
trap 'remote_err "Unexpected error"' ERR

APP_NAME="$REPO_NAME"
CONFIG_FILE="/etc/nginx/sites-available/\$APP_NAME"

sudo tee \$CONFIG_FILE > /dev/null <<NGINX
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:$APP_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX

sudo ln -sf \$CONFIG_FILE /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default || true
sudo nginx -t || remote_err "Nginx config test failed"
sudo systemctl reload nginx || remote_err "Nginx reload failed"

# Optional SSL placeholder (uncomment to enable Certbot setup)
# sudo apt install -y certbot python3-certbot-nginx
# sudo certbot --nginx --non-interactive --agree-tos --email your@email.com -d yourdomain.com

remote_log "Nginx configured as reverse proxy"
EOF

# 8. Validate Deployment
log "Validating deployment on remote..."
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" <<EOF || err "Validation failed"
set -euo pipefail
remote_log() { echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$*" | tee -a /tmp/deploy.log; }
remote_err() { remote_log "ERROR: \$*" >&2; exit 1; }
trap 'remote_err "Unexpected error"' ERR

if ! systemctl is-active --quiet docker; then remote_err "Docker service not running"; fi
if ! systemctl is-active --quiet nginx; then remote_err "Nginx service not running"; fi

APP_NAME="$REPO_NAME"
if [ $USE_COMPOSE -eq 1 ]; then
  cd /home/$SSH_USER/$REPO_NAME
  if [ \$(docker-compose ps -q | wc -l) -eq 0 ]; then remote_err "No active containers"; fi
else
  if ! docker ps | grep -q \$APP_NAME; then remote_err "Container not active"; fi
fi

curl -f http://localhost || remote_err "Local curl to Nginx (port 80) failed"
curl -f http://localhost:$APP_PORT || remote_err "Direct curl to app port failed"

remote_log "Deployment validated successfully"
EOF

# Local remote test
log "Testing accessibility from local machine..."
if curl -f "http://$SERVER_IP"; then
  log "Remote curl successful"
else
  log "WARNING: Remote curl failed - check server firewall, security groups, or if port 80 is exposed"
fi

log "Deployment completed successfully. Logs available in $LOG_FILE and remote /tmp/deploy.log"

