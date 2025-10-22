

#### 🧱 1. Bash Script to deploy a Dockerized Nginx Server

Right before **Usage**, summarize minimal steps for advanced users:

```bash
# Quick Start
git clone <your-repo-url>
cd <repo-dir>
chmod +x deploy_script.sh
./deploy_script.sh
```

*(Optional: include `--no-sudo` or `--skip-nginx` flags if your script supports CLI args.)*

---

#### ⚙️ 2. Include an Example Run

Show what a typical session looks like, so users know what to expect:

```bash
$ bash deploy_script.sh
Enter GitHub repository URL: https://github.com/anthonyusoro/myapp.git
Enter SSH username: ubuntu
Enter Server IP address: 192.168.1.100
Enter SSH key path: ~/.ssh/id_rsa
Does the remote server have sudo privileges? [Y/n]: y
Cloning repository...
Testing SSH connection...
Installing Docker (if needed)...
Deploying container...
Deployment completed successfully!
Access your app at: http://192.168.1.100
```

---

#### 🪣 3. Expand “Logging” Section

Clarify where logs are stored and what users should look for:

````markdown
### Logs
All deployment actions are logged in the `deploy_YYYYMMDD_HHMMSS.log` file located in the same directory as the script.  
To view logs in real-time during execution:
```bash
tail -f deploy_20251022_153045.log
````

````

---

#### 🧰 4. Add Optional Environment Variable Support
Mention that users can bypass prompts by exporting variables:
```bash
export GITHUB_REPO="https://github.com/username/repo.git"
export SSH_USER="ubuntu"
export SSH_HOST="192.168.1.100"
export SSH_KEY_PATH="~/.ssh/id_rsa"
bash deploy_script.sh
````

*(This is great for CI/CD or cron jobs.)*

---

#### 🔐 5. Security Note for Personal Access Tokens

Add a small warning:

> ⚠️ **Security Tip:** If using a GitHub Personal Access Token (PAT), avoid hard-coding it in the script. Use environment variables or a `.env` file excluded via `.gitignore`.

---

#### 🧩 6. Add Optional “Rollback Strategy” Section

Even if it’s manual for now:

> **Rollback:**
> If deployment fails, you can manually restart the previous container using:
>
> ```bash
> docker ps -a
> docker start <old_container_id>
> ```

---
👤 Author Information
Name: Anthony Usoro
Slack Username: @anthonyusoro
Project: Bash script for automating the deployment of a Dockerized application to a remote Linux server (assumed Ubuntu/Debian-based).
