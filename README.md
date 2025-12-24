# Movie Manager Project 🎬

A comprehensive DevOps showcase project deploying a **Three-Tier Web Application** (React Frontend + Node.js Backend + MongoDB) on **AWS EKS**, featuring a complete CI/CD pipeline with **Jenkins**, and observability with **Prometheus & Grafana**.

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                    AWS Cloud                                     │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                              VPC (10.0.0.0/16)                            │  │
│  │                                                                           │  │
│  │  ┌─────────────────────────┐    ┌─────────────────────────────────────┐  │  │
│  │  │    Public Subnets       │    │         Private Subnets             │  │  │
│  │  │                         │    │                                     │  │  │
│  │  │  ┌───────────────────┐  │    │  ┌─────────────────────────────┐   │  │  │
│  │  │  │  Jenkins Server   │  │    │  │      EKS Cluster (depi-eks) │   │  │  │
│  │  │  │  (EC2 - t3.medium)│  │    │  │                             │   │  │  │
│  │  │  │    :8080 (UI)     │  │    │  │  ┌─────────┐ ┌─────────┐   │   │  │  │
│  │  │  │    :22 (SSH)      │  │    │  │  │Frontend │ │ Backend │   │   │  │  │
│  │  │  └───────────────────┘  │    │  │  │  Pods   │ │  Pods   │   │   │  │  │
│  │  │                         │    │  │  │  :3000  │ │  :5000  │   │   │  │  │
│  │  │  ┌───────────────────┐  │    │  │  └────┬────┘ └────┬────┘   │   │  │  │
│  │  │  │   ALB (Ingress)   │◄─┼────┼──┼───────┴──────────┘         │   │  │  │
│  │  │  │  HTTP :80         │  │    │  │                             │   │  │  │
│  │  │  └───────────────────┘  │    │  │  ┌─────────┐ ┌───────────┐ │   │  │  │
│  │  │                         │    │  │  │ MongoDB │ │ EBS (gp3) │ │   │  │  │
│  │  └─────────────────────────┘    │  │  │  :27017 │◄┤   PVC     │ │   │  │  │
│  │                                 │  │  └─────────┘ └───────────┘ │   │  │  │
│  │                                 │  └─────────────────────────────┘   │  │  │
│  │                                 └─────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                  │
│   ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────────────┐  │
│   │     ECR      │    │   Route 53   │    │  Monitoring (kube-prometheus)   │  │
│   │  (Images)    │    │   (DNS)      │    │  Prometheus + Grafana + Alerts  │  │
│   └──────────────┘    └──────────────┘    └──────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────┘

                              ┌───────────────┐
           Internet ─────────►│   Users/API   │
                              └───────────────┘
```

### Infrastructure Components
| Component | Technology | Purpose |
|-----------|------------|---------|
| **Compute** | Amazon EKS | Managed Kubernetes cluster with node groups |
| **CI/CD** | Jenkins on EC2 | Automated build, push, and deploy pipeline |
| **Storage** | AWS EBS (gp3) | Persistent volume for MongoDB data |
| **Networking** | AWS ALB | Ingress controller for HTTP traffic routing |
| **Monitoring** | Prometheus + Grafana | Metrics collection and visualization |

### Application Stack
| Layer | Technology | Port |
|-------|------------|------|
| **Frontend** | React.js (Vite) | 3000 |
| **Backend** | Node.js + Express | 5000 |
| **Database** | MongoDB | 27017 |

---

---

## 🧩 Project Big Picture & Workflow

This diagram illustrates the **complete DevOps lifecycle**, showing how the tools interact from code commit to production monitoring.

```
                                  🚀 CI/CD PIPELINE (Jenkins)
                                  ───────────────────────────
                                         │
    👨‍💻 Developer                         │       🐳 Docker Build
    │ (git push)                         │      ┌───────────────┐
    ▼                                    ▼      │               │
  ┌──────────┐   run          ┌──────────────┐  │  ┌─────────┐  │    push    ┌─────────────┐
  │  GitHub  │───────────────►│    Jenkins   │──┼─►│  Image  │──┼───────────►│  Amazon ECR │
  │ (Source) │                │  (on EC2)    │  │  └─────────┘  │            │ (Registry)  │
  └──────────┘                └──┬────────┬──┘  └───────────────┘            └──────┬──────┘
                                 │        │                                         │
                                 │        │ (kubectl apply)                         │ (pull image)
             (terraform apply)   │        │                                         │
                                 │        ▼                                         ▼
  ┌──────────────────────────────┼─────────────────────────────────────────────────────────────┐
  │  INFRASTRUCTURE AS CODE      │                   RUNTIME ENVIRONMENT (AWS)                 │
  │                              │                                                             │
  │    ┌──────────────┐          │          ┌──────────────────────────────────────────────┐   │
  │    │  Terraform   │          │          │           Amazon EKS Cluster                 │   │
  │    │ (Provision)  │──────────┘          │                                              │   │
  │    └──────────────┘ Creates             │   ┌─────────────┐      ┌─────────────┐       │   │
  │           │                             │   │  Frontend   │      │   Backend   │       │   │
  │           ▼                             │   │    Pod      │◄────►│     Pod     │       │   │
  │    ┌──────────────┐                     │   └─────────────┘      └──────┬──────┘       │   │
  │    │     AWS      │                     │          ▲                    │              │   │
  │    │  Resources   │                     │          │                    ▼              │   │
  │    │ (VPC, EKS,   │                     │          │             ┌─────────────┐       │   │
  │    │  IAM, EC2)   │                     │          │             │   MongoDB   │       │   │
  │    └──────────────┘                     │          │             │     Pod     │       │   │
  │                                         │          │             └─────────────┘       │   │
  │                                         └──────────┼───────────────────────────────────┘   │
  │                                                    │                                       │
  │                                                    │ (Route Traffic)                       │
  │                                                    │                                       │
  │                                         ┌──────────┴──────────┐                            │
  │                                         │      AWS ALB        │                            │
  │                                         │ (Load Balancer)     │                            │
  │                                         └──────────┬──────────┘                            │
  │                                                    │                                       │
  └────────────────────────────────────────────────────┼───────────────────────────────────────┘
                                                       │
                                                       ▼
                                                🌍 End Users
```

### 🛠️ Tools & Technologies Stack

| Phase | Tool | Logo | Description |
|-------|------|------|-------------|
| **Source Control** | **Git / GitHub** | 🐙 | Stores code and history. Triggers builds. |
| **CI/CD** | **Jenkins** | 🤵 | Automates building images and deploying manifests. |
| **Infrastructure** | **Terraform** | 💜 | Provisions VPC, EKS, and IAM roles as code. |
| **Containerization**| **Docker** | 🐳 | Packages the app into portable images. |
| **Orchestration** | **Kubernetes (EKS)**| ☸️ | Manages and scales the application containers. |
| **Registry** | **Amazon ECR** | 📦 | Securely stores Docker images. |
| **Database** | **MongoDB** | 🍃 | NoSQL database for storing movie data. |
| **Monitoring** | **Prometheus** | 🔥 | Collects metrics from the cluster. |
| **Visualization** | **Grafana** | 📊 | Displays metrics on dashboards. |

---

## 📂 Repository Structure

```
├── app/                  # Application Source Code
│   ├── backend/          # Node.js API + Dockerfile
│   ├── frontend/         # React App + Dockerfile
│   └── docker-compose.yml # Local development setup
├── infra/                # Infrastructure as Code (Terraform)
│   ├── eks/              # EKS Cluster + Jenkins EC2 + IAM
│   ├── monitoring/       # Prometheus & Grafana Setup
│   └── addons/           # Helper scripts (AWS LBC, etc.)
├── k8s/                  # Kubernetes Manifests (App & DB)
├── scripts/              # Utility scripts
├── Jenkinsfile           # CI/CD Pipeline Definition
├── pre_destroy_check.sh  # Safety check script before destroy
└── README.md             # This file
```

---

## 🚀 Getting Started

### 1. Local Development (Docker Compose)
Run the application locally without AWS.

```bash
cd app
docker compose up --build
```
- Frontend: [http://localhost:3000](http://localhost:3000)
- Backend: [http://localhost:5000/api/movies](http://localhost:5000/api/movies)
- MongoDB: `mongodb://localhost:27018/movie_manager`

If you change frontend API envs (like `VITE_API_BASE_URL`), rebuild without cache:
```bash
cd app
docker compose build --no-cache frontend
docker compose up -d --force-recreate frontend
```

To seed the database locally:
```bash
docker compose exec backend npm run seed
```

---

## ☁️ AWS Deployment Guide

### Prerequisites
- AWS CLI v2 configured.
- Terraform installed.
- `kubectl` installed.

### Step 1: Provision Infrastructure (EKS + Jenkins)
This step creates the EKS cluster and a Jenkins Server on EC2.

```bash
cd infra/eks
terraform init
terraform apply -auto-approve
```

**Terraform Outputs to note:**
- `jenkins_url`: URL to access Jenkins.
- `jenkins_public_ip`: IP of Jenkins server.
- `cluster_name`: Name of the EKS cluster.
- `jenkins_ssh_hint`: Command to SSH into Jenkins.

### Step 2: Configure Local `kubectl`
Connect your local terminal to the new EKS cluster.

```bash
aws eks update-kubeconfig --region us-east-1 --name <CLUSTER_NAME>
```

### Step 3: Install AWS Load Balancer Controller (LBC)
Crucial for Ingress to work. We use a helper script for this.

```bash
# From repo root
cd infra/addons
chmod +x aws-lbc-cli.sh
./aws-lbc-cli.sh --no-sample
```
*Note: Ensure your `kubectl` context is set to the correct cluster.*

### Step 4: Deploy Monitoring (Optional)
Deploys Prometheus and Grafana.

```bash
cd infra/monitoring
terraform init
terraform apply -auto-approve
```
*Use `kubectl get ingress -n monitoring` to find the Grafana URL.*

---

## 🤖 CI/CD with Jenkins

The infrastructure includes a pre-configured Jenkins server.

1. **Access Jenkins**: Open `http://<JENKINS_PUBLIC_IP>:8080` in your browser.
2. **Initial Setup**: SSH into the box to get the initial admin password if prompted (or check Terraform output logs/userdata).
3. **Pipeline**: Create a new Pipeline job and point it to this repository.
4. **Run Build**: The `Jenkinsfile` will:
   - Build Docker images.
   - Push to Amazon ECR.
   - Deploy/Update manifests to EKS.

---

## 🛠 Manual Kubernetes Deployment
If you prefer to deploy manually without Jenkins:

```bash
# Apply Database & Seeding
kubectl apply -f k8s/mongo-pvc.yaml
kubectl apply -f k8s/mongo.yaml
kubectl apply -f k8s/mongo-seed-configmap.yaml
kubectl apply -f k8s/mongo-seed-job.yaml

# Apply App
kubectl apply -f k8s/movie-manager-backend.yaml
kubectl apply -f k8s/movie-manager-frontend.yaml
kubectl apply -f k8s/movie-manager-ingress.yaml
```

---

## 🧹 Cleanup & Teardown

**IMPORTANT**: Before destroying infrastructure, ensure all Load Balancers are deleted to avoid dangling resources.

Run the safety check script:
```bash
./pre_destroy_check.sh
```

If checks pass:
1. Destroy Monitoring: `terraform destroy` in `infra/monitoring`
2. Destroy EKS/Jenkins: `terraform destroy` in `infra/eks`

