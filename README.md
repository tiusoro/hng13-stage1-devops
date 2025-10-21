# deploy.sh README

## Overview
This is a production-grade Bash script for automating the deployment of a Dockerized application to a remote Linux server (assumed Ubuntu/Debian-based). It handles cloning from Git, remote setup, deployment (with support for Dockerfile or docker-compose.yml), Nginx reverse proxy configuration, validation, logging, error handling, and idempotency.

## Features
- **Input Collection**: Prompts for Git details, SSH credentials, and app port with basic validation.
- **Git Operations**: Clones or pulls the repo using PAT, switches to specified branch.
- **Remote Preparation**: Installs Docker, Docker Compose, Nginx if missing; starts/enables services.
- **Deployment**: Transfers files via rsync, builds/runs container(s) idempotently (stops/removes old ones).
- **Nginx Setup**: Configures reverse proxy from port 80 to app port; optional SSL placeholder.
- **Validation**: Checks services, container health, and accessibility via curl.
- **Logging & Errors**: Logs to timestamped file locally and /tmp/deploy.log remotely; traps errors.
- **Idempotency**: Safe to re-run; handles existing setups gracefully.
- **Cleanup**: Optional `--cleanup` flag to remove resources.

## Assumptions
- Remote server is Ubuntu/Debian (uses apt).
- SSH key has no passphrase (or agent handles it).
- Repo contains either `Dockerfile` (for single container) or `docker-compose.yml` (preferred for multi-container).
- App listens on the specified internal port inside the container.
- Server IP is publicly accessible for remote curl test (adjust firewall if needed).
- No existing conflicts on ports (e.g., app port not 80/443).
- POSIX-compliant; tested on Bash 4+.

## Usage
1. Make executable: `chmod +x deploy.sh`
2. Run: `./deploy.sh`
3. For cleanup: `./deploy.sh --cleanup`

## Limitations
- Assumes home directory access on remote (/home/$USER).
- Basic validation; no advanced Git/SSH error recovery.
- SSL is placeholder-only (manual Certbot setup needed).
- No support for non-Debian distros (e.g., CentOS); modify install commands if needed.

## Troubleshooting
- Check logs in `deploy_YYYYMMDD.log` and remote `/tmp/deploy.log`.
- Ensure SSH key is added to remote authorized_keys.
- If transfer fails, verify rsync/ssh connectivity.
- For customizations, edit the script (e.g., add domain to Nginx).

Push this to your GitHub repo as `deploy.sh` and `README.md`.