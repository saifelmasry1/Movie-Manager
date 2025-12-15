#!/usr/bin/env bash
set -euo pipefail

# Log everything (helps debugging user-data)
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

export DEBIAN_FRONTEND=noninteractive

echo "==[1/7] Update packages =="
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release unzip jq git

echo "==[2/7] Install Java (required by Jenkins) =="
apt-get install -y openjdk-17-jre

echo "==[3/7] Install Jenkins (Debian/Ubuntu repo) =="
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee /etc/apt/keyrings/jenkins-keyring.asc >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | tee /etc/apt/sources.list.d/jenkins.list >/dev/null

apt-get update -y
apt-get install -y jenkins

systemctl enable jenkins
systemctl restart jenkins

echo "==[4/7] Install Docker =="
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

ARCH="$(dpkg --print-architecture)"
UBU_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBU_CODENAME} stable" \
  | tee /etc/apt/sources.list.d/docker.list >/dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl restart docker

# Allow Jenkins to run Docker
usermod -aG docker jenkins
systemctl restart jenkins

echo "==[5/7] Install kubectl =="
KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

echo "==[6/7] Install Helm =="
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "==[7/7] Install Terraform + AWS CLI v2 =="
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com ${UBU_CODENAME} main" \
  | tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
apt-get update -y
apt-get install -y terraform

tmpdir="$(mktemp -d)"
pushd "$tmpdir"
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install --update
popd
rm -rf "$tmpdir"

echo "== Done =="
echo "Jenkins should be up on port 8080."
echo "Initial admin password:"
echo "  sudo cat /var/lib/jenkins/secrets/initialAdminPassword"


