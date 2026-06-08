# Secure CI/CD Pipeline — Practice Repo

A fully working Spring Boot app wired up for a production-grade Jenkins pipeline with:
- SonarQube (SAST + quality gate)
- Trivy (container image CVE scanning)
- Docker multi-stage build (non-root, minimal base)
- Kubernetes deployment with readiness/liveness probes and rollback

---

## Repository structure

```
.
├── Dockerfile                  # Multi-stage, non-root, Alpine JRE
├── Jenkinsfile                 # Full pipeline: test → sonar → trivy → push → deploy
├── docker-compose.yml          # Runs SonarQube + Postgres locally
├── app/
│   ├── pom.xml                 # Spring Boot + Actuator + JaCoCo + SonarQube plugin
│   └── src/
│       ├── main/java/com/demo/app/
│       │   ├── Application.java
│       │   └── HelloController.java
│       └── test/java/com/demo/app/
│           └── HelloControllerTest.java
├── k8s/
│   ├── deployment.yaml         # Non-root, readOnly filesystem, resource limits
│   └── service.yaml            # NodePort (Minikube) or LoadBalancer (EKS)
├── sonar/
│   └── sonar-project.properties
├── scripts/
│   └── jenkins-setup.sh        # Installs Docker, Trivy, kubectl on Jenkins host
└── .github/workflows/
    └── ci.yml                  # GitHub Actions mirror (optional reference)
```

---

## Prerequisites

| Tool | Where | Purpose |
|---|---|---|
| Jenkins | EC2 t3.medium | Pipeline orchestrator |
| SonarQube | Docker (same host) | SAST + quality gate |
| Docker | Jenkins host | Build images |
| Trivy | Jenkins host | CVE scan |
| kubectl | Jenkins host | Deploy to K8s |
| Minikube or EKS | Separate or same host | Kubernetes target |

---

## Step-by-step setup

### 1. Clone this repo

```bash
git clone https://github.com/YOUR_USERNAME/secure-cicd-pipeline.git
cd secure-cicd-pipeline
```

### 2. Set up Jenkins host

```bash
# Run on your EC2 / VM after Jenkins is installed
chmod +x scripts/jenkins-setup.sh
./scripts/jenkins-setup.sh
```

Then restart Jenkins:
```bash
sudo systemctl restart jenkins
```

### 3. Start SonarQube

```bash
docker compose up -d
# Open http://YOUR_HOST:9000
# Default login: admin / admin (change on first login)
```

> If SonarQube fails to start: `sudo sysctl -w vm.max_map_count=262144`

### 4. Generate a SonarQube token

1. Log into SonarQube → `My Account → Security → Generate Token`
2. Copy the token

### 5. Add Jenkins credentials

Go to `Manage Jenkins → Credentials → System → Global → Add Credential`:

| ID | Kind | Value |
|---|---|---|
| `github-token` | Secret text | GitHub Personal Access Token |
| `sonar-token` | Secret text | SonarQube token from step 4 |
| `registry-creds` | Username/Password | DockerHub username + password |
| `kubeconfig` | Secret file | Your `~/.kube/config` file |

### 6. Configure SonarQube in Jenkins

`Manage Jenkins → System → SonarQube Servers`:
- Name: `SonarQube`
- URL: `http://localhost:9000`
- Token: select `sonar-token` credential

### 7. Update the Jenkinsfile

Edit `Jenkinsfile` line 10:
```groovy
REGISTRY = "yourdockerhubusername"   // ← change this
```

Edit `Jenkinsfile` line 12 if using ECR:
```groovy
REGISTRY = "123456789012.dkr.ecr.ap-south-1.amazonaws.com"
```

### 8. Create the Jenkins pipeline job

1. New Item → Pipeline
2. Build Triggers → check `GitHub hook trigger for GITScm polling`
3. Pipeline Definition → `Pipeline script from SCM`
4. SCM → Git → add your repo URL + `github-token` credential
5. Branch → `*/main`
6. Script Path → `Jenkinsfile`

### 9. Add the GitHub webhook

In your GitHub repo → `Settings → Webhooks → Add webhook`:
- Payload URL: `http://YOUR_JENKINS_IP:8080/github-webhook/`
- Content type: `application/json`
- Events: `Just the push event`

### 10. Push and watch it run

```bash
git add .
git commit -m "trigger pipeline"
git push origin main
```

Watch the build in Jenkins. Each stage should go green. If Trivy finds
HIGH/CRITICAL CVEs the build will fail — that's intentional.

---

## Testing the deployed app

```bash
# Minikube
minikube service secure-cicd-demo --url
curl http://$(minikube ip):30080/
curl http://$(minikube ip):30080/health

# EKS / cloud LoadBalancer
kubectl get svc secure-cicd-demo
curl http://EXTERNAL_IP/health
```

Expected responses:
```json
{"message":"Secure CI/CD Pipeline Demo","status":"running"}
{"status":"UP"}
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Trivy scan fails on HIGH CVEs | Update base image in Dockerfile or use `--ignore-unfixed` flag |
| SonarQube quality gate fails | Check `target/site/jacoco/jacoco.xml` exists (run `mvn test` first) |
| `docker: permission denied` on Jenkins | `sudo usermod -aG docker jenkins && sudo systemctl restart jenkins` |
| Webhook returning 403 | Check Jenkins security realm allows anonymous read, or configure webhook secret |
| Pod `CrashLoopBackOff` | `kubectl logs deploy/secure-cicd-demo` — likely readOnlyRootFilesystem issue |

---

## Credentials reference (Jenkins IDs used in Jenkinsfile)

```
github-token     → GitHub PAT (repo + admin:repo_hook scopes)
sonar-token      → SonarQube user token
registry-creds   → Docker registry username + password
kubeconfig       → Kubernetes config file (secret file credential)
```
