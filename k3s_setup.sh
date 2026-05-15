#!/bin/bash

set -e

export DEBIAN_FRONTEND=noninteractive

echo "=================================================================="
echo " COMPLETE K3s DEVSECOPS PLATFORM SETUP"
echo " Ubuntu 24.04 LTS"
echo " Docker | Jenkins | SonarQube | k3s | Helm | Trivy"
echo " Prometheus | Grafana | kubectl"
echo "=================================================================="

# ----------------------------------------------------------
# VERIFY UBUNTU
# ----------------------------------------------------------

if ! command -v apt >/dev/null 2>&1; then
    echo "Ubuntu/Debian system required"
    exit 1
fi

# ----------------------------------------------------------
# ARCHITECTURE DETECTION
# ----------------------------------------------------------

ARCH=$(uname -m)

case $ARCH in
    x86_64)
        AWS_ARCH="x86_64"
        K8S_ARCH="amd64"
        ;;
    aarch64|arm64)
        AWS_ARCH="aarch64"
        K8S_ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "Detected Architecture:"
echo "AWS CLI : ${AWS_ARCH}"
echo "Kubernetes : ${K8S_ARCH}"

# ----------------------------------------------------------
# UPDATE SERVER
# ----------------------------------------------------------

echo "Updating Server..."

sudo apt update -y

sudo apt upgrade -y

# ----------------------------------------------------------
# INSTALL REQUIRED PACKAGES
# ----------------------------------------------------------

echo "Installing Required Packages..."

sudo apt install -y \
curl \
wget \
git \
jq \
unzip \
gnupg \
ca-certificates \
apt-transport-https \
software-properties-common \
lsb-release \
fontconfig \
openjdk-21-jre

# ----------------------------------------------------------
# VERIFY JAVA
# ----------------------------------------------------------

echo "Verifying Java Installation..."

java -version

# ----------------------------------------------------------
# INSTALL DOCKER
# ----------------------------------------------------------

if ! command -v docker >/dev/null 2>&1; then

    echo "Installing Docker..."

    sudo install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt update -y

    sudo apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

fi

sudo systemctl enable docker

sudo systemctl restart docker

# ----------------------------------------------------------
# DOCKER PERMISSIONS
# ----------------------------------------------------------

CURRENT_USER=${SUDO_USER:-ubuntu}

sudo usermod -aG docker ${CURRENT_USER}

# ----------------------------------------------------------
# INSTALL JENKINS
# ----------------------------------------------------------

if ! dpkg -l | grep -q jenkins; then

    echo "Installing Jenkins..."

    sudo mkdir -p /etc/apt/keyrings

    curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
    | sudo tee /etc/apt/keyrings/jenkins-keyring.asc > /dev/null

    echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] \
    https://pkg.jenkins.io/debian-stable binary/" \
    | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

    sudo apt update -y

    sudo apt install -y jenkins

fi

sudo systemctl daemon-reload

sudo systemctl enable jenkins

sudo systemctl restart jenkins || true

# ----------------------------------------------------------
# ADD JENKINS TO DOCKER GROUP
# ----------------------------------------------------------

if id "jenkins" &>/dev/null; then

    sudo usermod -aG docker jenkins

    sudo systemctl restart jenkins || true

fi

# ----------------------------------------------------------
# INSTALL AWS CLI v2
# ----------------------------------------------------------

if ! command -v aws >/dev/null 2>&1; then

    echo "Installing AWS CLI..."

    curl -fsSL \
    "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" \
    -o awscliv2.zip

    unzip -o awscliv2.zip

    sudo ./aws/install \
    --bin-dir /usr/local/bin \
    --install-dir /usr/local/aws-cli \
    --update

    rm -rf aws awscliv2.zip

fi

# ----------------------------------------------------------
# VERIFY AWS CLI
# ----------------------------------------------------------

aws --version

# ----------------------------------------------------------
# INSTALL kubectl
# ----------------------------------------------------------

if ! command -v kubectl >/dev/null 2>&1; then

    echo "Installing kubectl..."

    KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)

    curl -fsSLO \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${K8S_ARCH}/kubectl"

    chmod +x kubectl

    sudo mv kubectl /usr/local/bin/

fi

# ----------------------------------------------------------
# VERIFY kubectl
# ----------------------------------------------------------

kubectl version --client

# ----------------------------------------------------------
# INSTALL HELM
# ----------------------------------------------------------

if ! command -v helm >/dev/null 2>&1; then

    echo "Installing Helm..."

    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

fi

# ----------------------------------------------------------
# VERIFY HELM
# ----------------------------------------------------------

helm version

# ----------------------------------------------------------
# INSTALL TRIVY
# ----------------------------------------------------------

if ! command -v trivy >/dev/null 2>&1; then

    echo "Installing Trivy..."

    sudo mkdir -p /etc/apt/keyrings

    curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
    | sudo gpg --dearmor -o /etc/apt/keyrings/trivy.gpg

    echo \
    "deb [signed-by=/etc/apt/keyrings/trivy.gpg] \
    https://aquasecurity.github.io/trivy-repo/deb generic main" \
    | sudo tee /etc/apt/sources.list.d/trivy.list > /dev/null

    sudo apt update -y

    sudo apt install -y trivy

fi

# ----------------------------------------------------------
# VERIFY TRIVY
# ----------------------------------------------------------

trivy --version

# ----------------------------------------------------------
# INSTALL k3s
# ----------------------------------------------------------

if ! command -v k3s >/dev/null 2>&1; then

    echo "Installing k3s Kubernetes..."

    curl -sfL https://get.k3s.io | sh -

fi

# ----------------------------------------------------------
# WAIT FOR K3s
# ----------------------------------------------------------

echo "Waiting For k3s Cluster To Become Ready..."

sleep 30

# ----------------------------------------------------------
# CONFIGURE KUBECONFIG
# ----------------------------------------------------------

mkdir -p ~/.kube

sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

sudo chown ${CURRENT_USER}:${CURRENT_USER} ~/.kube/config

export KUBECONFIG=~/.kube/config

# ----------------------------------------------------------
# VERIFY K3s CLUSTER
# ----------------------------------------------------------

echo "Checking Kubernetes Cluster..."

kubectl get nodes

kubectl get pods -A

# ----------------------------------------------------------
# FIX SYSCTL FILE ISSUE
# ----------------------------------------------------------

sudo touch /etc/sysctl.conf

# ----------------------------------------------------------
# SONARQUBE KERNEL SETTINGS
# ----------------------------------------------------------

echo "Configuring SonarQube Kernel Settings..."

sudo sysctl -w vm.max_map_count=524288

sudo sysctl -w fs.file-max=131072

if ! grep -q "vm.max_map_count=524288" /etc/sysctl.conf; then

    echo "vm.max_map_count=524288" \
    | sudo tee -a /etc/sysctl.conf

fi

if ! grep -q "fs.file-max=131072" /etc/sysctl.conf; then

    echo "fs.file-max=131072" \
    | sudo tee -a /etc/sysctl.conf

fi

# ----------------------------------------------------------
# INSTALL SONARQUBE
# ----------------------------------------------------------

if ! sudo docker ps -a --format '{{.Names}}' | grep -q "^sonarqube$"; then

    echo "Installing SonarQube..."

    sudo docker volume create sonarqube_data

    sudo docker volume create sonarqube_logs

    sudo docker volume create sonarqube_extensions

    sudo docker run -d \
    --name sonarqube \
    --restart unless-stopped \
    -p 9000:9000 \
    -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
    -v sonarqube_data:/opt/sonarqube/data \
    -v sonarqube_logs:/opt/sonarqube/logs \
    -v sonarqube_extensions:/opt/sonarqube/extensions \
    sonarqube:lts-community

fi

# ----------------------------------------------------------
# WAIT FOR SONARQUBE
# ----------------------------------------------------------

echo "Waiting For SonarQube To Initialize..."

sleep 60

# ----------------------------------------------------------
# INSTALL PROMETHEUS + GRAFANA
# ----------------------------------------------------------

echo "Installing Monitoring Stack..."

kubectl create namespace monitoring \
--dry-run=client -o yaml | kubectl apply -f -

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true

helm repo update

cat <<EOF > monitoring-values.yaml

grafana:
  service:
    type: NodePort
    nodePort: 32000

prometheus:
  service:
    type: ClusterIP

alertmanager:
  service:
    type: ClusterIP

EOF

helm upgrade --install monitoring \
prometheus-community/kube-prometheus-stack \
-n monitoring \
-f monitoring-values.yaml \
--create-namespace \
--timeout 30m

# ----------------------------------------------------------
# WAIT FOR MONITORING PODS
# ----------------------------------------------------------

echo "Waiting For Monitoring Pods..."

kubectl wait \
--for=condition=Ready pods \
--all \
-n monitoring \
--timeout=900s || true

# ----------------------------------------------------------
# VERIFY SERVICES
# ----------------------------------------------------------

kubectl get svc -n monitoring

# ----------------------------------------------------------
# DISPLAY TOOL VERSIONS
# ----------------------------------------------------------

echo ""
echo "=========================================================="
echo " INSTALLED TOOL VERSIONS"
echo "=========================================================="

docker --version || true

java -version || true

aws --version || true

kubectl version --client || true

helm version || true

trivy --version || true

jenkins --version || true

# ----------------------------------------------------------
# JENKINS PASSWORD
# ----------------------------------------------------------

echo ""
echo "=========================================================="
echo " JENKINS INITIAL PASSWORD"
echo "=========================================================="

sudo cat /var/lib/jenkins/secrets/initialAdminPassword || true

# ----------------------------------------------------------
# GRAFANA PASSWORD
# ----------------------------------------------------------

echo ""
echo "=========================================================="
echo " GRAFANA ADMIN PASSWORD"
echo "=========================================================="

kubectl -n monitoring get secret monitoring-grafana \
-o jsonpath="{.data.admin-password}" | base64 -d

echo ""

# ----------------------------------------------------------
# PUBLIC IP
# ----------------------------------------------------------

PUBLIC_IP=$(curl -s ifconfig.me || true)

# ----------------------------------------------------------
# ACCESS URLS
# ----------------------------------------------------------

echo ""
echo "=========================================================="
echo " ACCESS URLS"
echo "=========================================================="

echo "Jenkins:"
echo "http://${PUBLIC_IP}:8080"

echo ""

echo "SonarQube:"
echo "http://${PUBLIC_IP}:9000"

echo ""

echo "Grafana:"
echo "http://${PUBLIC_IP}:32000"

echo ""

echo "Prometheus Port Forward:"
echo "kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring"

# ----------------------------------------------------------
# SECURITY GROUP REMINDER
# ----------------------------------------------------------

echo ""
echo "=========================================================="
echo " REQUIRED SECURITY GROUP PORTS"
echo "=========================================================="

echo "22      -> SSH"
echo "8080    -> Jenkins"
echo "9000    -> SonarQube"
echo "32000   -> Grafana NodePort"
echo "30000-32767 -> Kubernetes NodePorts"

# ----------------------------------------------------------
# FINAL MESSAGE
# ----------------------------------------------------------

echo ""
echo "=========================================================="
echo " COMPLETE DEVSECOPS PLATFORM INSTALLED SUCCESSFULLY ✅"
echo "=========================================================="

echo "IMPORTANT:"
echo "1. Reboot server after installation"
echo "2. Run: newgrp docker"
echo "3. Open required Security Group ports"
echo "=========================================================="