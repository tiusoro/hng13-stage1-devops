#!/bin/bash

# ==========================
# Improved Safe Auto-Deployment Script
# ==========================

set -e

LOGFILE="deploy_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -i "$LOGFILE") 2>&1

# Colors
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

echo -e "${GREEN}=== DEPLOYMENT STARTED ===${NC}"

# --- Customizable Variables ---
APP_NAME="myapp"
CONTAINER_INTERNAL_PORT="80"
CONTAINER_HOST_PORT="8080"

# --- Prompt for User Inputs ---
read -p "Enter GitHub repository URL: " REPO_URL
read -s -p "Enter Personal Access Token (leave empty if public repo): " TOKEN
echo
read -p "Enter Branch name: " BRANCH
read -p "Enter SSH username: " SSH_USER
read -p "Enter Server IP address: " SSH_HOST
read -p "Enter SSH port [default 22]: " SSH_PORT
SSH_PORT=${SSH_PORT:-22}
read -p "Enter SSH key path: " SSH_KEY
read -p "Can you use sudo on the remote server without password prompt? (y/n) [n]: " HAS_SUDO
HAS_SUDO=${HAS_SUDO:-n}
if [ "$HAS_SUDO" = "y" ]; then USE_SUDO="sudo "; else USE_SUDO=""; fi

# --- Parse repo name ---
REPO_NAME=$(basename -s .git "$REPO_URL")

# --- Prepare Git URL with token if provided ---
if [ -n "$TOKEN" ]; then
  AUTH_REPO_URL="https://${TOKEN}@${REPO_URL#https://}"
else
  AUTH_REPO_URL="$REPO_URL"
fi

# --- Clone or Pull Repository ---
if [ -d "$REPO_NAME/.git" ]; then
  echo -e "${YELLOW}[INFO] Repository exists. Pulling latest changes...${NC}"
  cd "$REPO_NAME"
  git remote set-url origin "$AUTH_REPO_URL"
  git pull origin "$BRANCH"
  git remote set-url origin "$REPO_URL"
  cd ..
else
  echo -e "${GREEN}[INFO] Cloning repository...${NC}"
  git clone -b "$BRANCH" "$AUTH_REPO_URL" "$REPO_NAME"
  cd "$REPO_NAME"
  git remote set-url origin "$REPO_URL"
  cd ..
fi

# --- Test SSH connectivity ---
echo -e "${YELLOW}[INFO] Testing SSH connectivity...${NC}"
if ssh -o BatchMode=yes -o ConnectTimeout=10 -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "echo connected" >/dev/null 2>&1; then
  echo -e "${GREEN}[INFO] SSH connection successful!${NC}"
else
  echo -e "${RED}[ERROR] SSH connection failed. Exiting.${NC}"
  exit 1
fi

# --- Copy Files (excluding .git using tar + scp) ---
echo -e "${YELLOW}[INFO] Copying files to remote server (excluding .git)...${NC}"
tar --exclude='.git' -czf "$REPO_NAME.tar.gz" "$REPO_NAME"

scp -i "$SSH_KEY" -P "$SSH_PORT" "$REPO_NAME.tar.gz" "$SSH_USER@$SSH_HOST:~/" || {
  echo -e "${RED}[ERROR] File transfer failed.${NC}"
  exit 1
}

ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" bash <<EOF
set -e
echo "[REMOTE] Extracting project files..."
rm -rf ~/$REPO_NAME
tar -xzf "$REPO_NAME.tar.gz" -C ~/
rm -f "$REPO_NAME.tar.gz"
EOF

rm -f "$REPO_NAME.tar.gz"

# --- Build and Run Docker ---
echo -e "${YELLOW}[INFO] Building Docker image and starting container...${NC}"
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" bash <<EOF
set -e
cd ~/$REPO_NAME

echo "[REMOTE] Building Docker image..."
docker build -t $APP_NAME .

echo "[REMOTE] Stopping old container..."
docker stop $APP_NAME >/dev/null 2>&1 || true
docker rm $APP_NAME >/dev/null 2>&1 || true

echo "[REMOTE] Starting new container on port $CONTAINER_HOST_PORT..."
docker run -d -p $CONTAINER_HOST_PORT:$CONTAINER_INTERNAL_PORT --name $APP_NAME $APP_NAME

echo "[REMOTE] Checking running containers..."
docker ps --filter "name=$APP_NAME"
EOF

# --- Configure Nginx Reverse Proxy ---
echo -e "${YELLOW}[INFO] Configuring Nginx reverse proxy...${NC}"
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" bash <<EOF
set -e
if [ ! -f /etc/nginx/sites-available/default ]; then
    echo "[WARN] Nginx may not be installed or accessible. Skipping configuration."
else
    echo "[REMOTE] Updating Nginx config..."
    cat <<NGINXCONF > ~/nginx_default.conf
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://localhost:$CONTAINER_HOST_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINXCONF

    if $USE_SUDO mv ~/nginx_default.conf /etc/nginx/sites-available/default; then
        if $USE_SUDO nginx -t; then
            $USE_SUDO systemctl reload nginx
            echo "[REMOTE] Nginx reloaded successfully."
        else
            echo "[ERROR] Nginx config test failed. Not reloading."
        fi
    else
        echo "[WARN] Could not update Nginx config due to permissions. Skipping reload."
    fi
fi
EOF

# --- Health Check ---
echo -e "${YELLOW}[INFO] Checking app response internally...${NC}"
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" bash <<EOF
curl -I http://localhost:$CONTAINER_HOST_PORT || echo "[WARN] Could not reach app internally."
EOF

echo -e "${GREEN}=== DEPLOYMENT COMPLETE ===${NC}"
echo "Check your app at: http://$SSH_HOST"
echo "Logs saved to: $LOGFILE"
