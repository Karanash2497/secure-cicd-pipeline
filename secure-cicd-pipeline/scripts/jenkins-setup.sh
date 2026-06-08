#!/usr/bin/env bash
# jenkins-setup.sh
# Run this on your Jenkins EC2 instance after Jenkins is installed.
# Installs Docker, Trivy, kubectl, and Java 21.
set -euo pipefail

echo "==> Updating system packages"
sudo apt-get update -y

# ── Java 21 ────────────────────────────────────────────────────────────────────
echo "==> Installing Java 21"
sudo apt-get install -y temurin-21-jdk 2>/dev/null || {
    sudo apt-get install -y openjdk-21-jdk
}

# ── Maven ─────────────────────────────────────────────────────────────────────
echo "==> Installing Maven"
sudo apt-get install -y maven

# ── Docker ────────────────────────────────────────────────────────────────────
echo "==> Installing Docker"
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Add jenkins user to docker group so Jenkins can run docker without sudo
sudo usermod -aG docker jenkins
echo "  Docker installed. Jenkins user added to docker group."

# ── Trivy ─────────────────────────────────────────────────────────────────────
echo "==> Installing Trivy"
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
  | sudo sh -s -- -b /usr/local/bin
trivy --version

# ── kubectl ───────────────────────────────────────────────────────────────────
echo "==> Installing kubectl"
KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
kubectl version --client

echo ""
echo "✓ Setup complete."
echo ""
echo "Next steps:"
echo "  1. Restart Jenkins:  sudo systemctl restart jenkins"
echo "  2. Run SonarQube:    docker run -d --name sonarqube -p 9000:9000 sonarqube:community"
echo "  3. Add credentials in Jenkins UI (github-token, registry-creds, kubeconfig, sonar-token)"
