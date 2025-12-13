# 🎬 Movie Manager on AWS EKS

Movie Manager is a full-stack demo app (React + Node.js + MongoDB) deployed on **Amazon EKS** using:

- **Terraform** for infrastructure (VPC, subnets, EKS, node groups, IAM…)
- **Docker** to containerize backend & frontend
- **Amazon ECR** as image registry
- **Kubernetes** manifests for MongoDB, backend, frontend & Ingress
- **AWS Load Balancer Controller** + **ALB Ingress**
- **Bash scripting** to automate ALB Controller installation (`infra/addons/aws-lbc-cli.sh`)

The final result:  
Browsing the ALB URL shows the Movie Manager UI with 12 seeded movies loaded from MongoDB running inside the cluster.

---

## 🏗 Architecture Overview

### High-level diagram

```text
                         +------------------------+
                         | 💻 Developer Laptop    |
                         | 🛠️ Terraform / Docker   |
                         +-----------+------------+
                                     |
                   docker push 🐳    | terraform apply 🏗️
                                     v
                         +------------------------+
                         | ☁️  AWS Account        |
                         +------------------------+
                                     |
           +-------------------------+--------------------------+
           |                                                    |
           v                                                    v
+---------------------+                           +------------------------+
| 📦 Amazon ECR       |                           | 🌐 VPC, Subnets, IAM,  |
| - movie-manager-    |<------ Terraform -------->| ☸️  EKS Cluster, Nodes |
|   backend           |                           +-----------+------------+
| - movie-manager-    |                                       |
|   frontend          |                                       |
+----------+----------+                                       |
           |                                      Worker nodes pull images 📥
           |  pull images                                  |
           v                                               v
   +-----------------------------+             +-----------------------------+
   | ☸️  EKS Cluster             |             | 📜 infra/addons/aws-lbc-cli.sh script    |
   |  (depi-eks, us-east-1)      |             | - OIDC provider             |
   |                             |             | - IAM policy (iam-policy)   |
   |  +-----------------------+  |             | - IAM ServiceAccount        |
   |  | ⚖️ AWS Load Balancer  |  |             | - Helm install ALB Ctrlr    |
   |  | Controller + Ingress  |  |             +-----------------------------+
   |  +-----------+-----------+  |
   |              |              |
   |   +----------+------------+ |
   |   | 🚦 Ingress (alb)      | |
   |   | movie-manager-ingress | |
   |   +----------+------------+ |
   |              |              |
   |   /                      /api
   |   |                      |
   |   v                      v
   |+----------------+   +----------------------+
   || 🕸️ SVC frontend|   | 🕸️ SVC backend     |
   || (ClusterIP:80) |   | (ClusterIP:5000)     |
   |+--------+-------+   +----------+-----------+
   |         |                      |
   |         v                      v
   |  +-------------+        +------------------+       +-----------------+
   |  | ⚛️ Frontend |        | 🔙 Backend       |       | 🍃 Mongo Service|
   |  | Pods (React)|        | Pods (Node.js)   |       | (ClusterIP:27017)|
   |  +-------------+        +--------+---------+       +--------+--------+
   |                               |                           |
   |                               v                           v
   |                         +-----------+             +-----------------+
   |                         | 🍃 MongoDB|             | 🍃 MongoDB Pod  |
   |                         +-----------+             +-----------------+
   +---------------------------------------------------------------+
```

### 🔧 Tech Stack

- **Cloud**: AWS (EKS, ECR, IAM, VPC, ALB)
- **IaC**: Terraform
- **Orchestration**: Kubernetes (EKS)
- **Containers**: Docker
- **Registry**: Amazon ECR
- **Ingress**: AWS Load Balancer Controller + ALB Ingress
- **Backend**: Node.js + Express + MongoDB driver
- **Frontend**: React (Vite) + Axios
- **Database**: MongoDB (running as a pod inside the cluster)
- **Bash scripts**: `infra/addons/aws-lbc-cli.sh` for ALB Controller

### 📂 Repository Layout (example)

Adjust paths if your layout is slightly different.

```text
.
├── app
│   ├── backend/                 # Node.js/Express API
│   └── frontend/                # React/Vite SPA
├── k8s
│   ├── mongo.yaml               # MongoDB Deployment + Service
│   ├── movie-manager-backend.yaml
│   ├── movie-manager-frontend.yaml
│   └── movie-manager-ingress.yaml
├── terraform/                   # VPC + EKS + node groups + IAM (Terraform)
├── scripts/
│   ├── infra/addons/aws-lbc-cli.sh           # CLI-ish Bash installer for AWS LBC + IngressClass
│   └── infra/addons/iam-policy.json          # AWS LBC IAM policy document
├── seed-movies.js               # MongoDB seed script (12 movies)
└── README.md
```

## ✅ Prerequisites

On your local machine:

1. **AWS account** + IAM user with permission to EKS, ECR, IAM, EC2, CloudFormation, VPC.
2. **Tools installed**:
   - `terraform`
   - `aws` (AWS CLI)
   - `kubectl`
   - `helm`
   - `eksctl`
   - `docker`
   - `bash`

Export some handy environment variables (change as needed):

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=163511166008
export CLUSTER_NAME=depi-eks
```

## 1️⃣ Provision Infrastructure with Terraform

From the Terraform folder:

```bash
cd infra/eks

terraform init
terraform plan
terraform apply
```

Wait until Terraform finishes and the EKS cluster + node group is created.

Update your local kubeconfig to talk to the new cluster:

```bash
aws eks update-kubeconfig \
  --name $CLUSTER_NAME \
  --region $AWS_REGION
```

Verify the cluster:

```bash
kubectl get nodes
```

You should see the worker nodes ready, and the core kube-system pods running.

## 2️⃣ Build & Push Docker Images to ECR

### 2.1 Create ECR repositories (first time only)

```bash
aws ecr create-repository \
  --repository-name movie-manager-backend \
  --region $AWS_REGION

aws ecr create-repository \
  --repository-name movie-manager-frontend \
  --region $AWS_REGION
```
If they already exist, the error is fine.

### 2.2 Login Docker to ECR

```bash
aws ecr get-login-password --region $AWS_REGION \
  | docker login \
      --username AWS \
      --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

### 2.3 Build backend image

```bash
cd app/backend

# Example tag
BACKEND_TAG=eks-v1

docker build \
  -t movie-manager-backend:$BACKEND_TAG \
  .
```

### 2.4 Build frontend image

The frontend needs to know where the backend API is.
In production (EKS) we use the same host and call the backend via `/api`, so we build with:

```bash
cd ../frontend

FRONTEND_TAG=eks-v2

docker build \
  -t movie-manager-frontend:$FRONTEND_TAG \
  --build-arg VITE_API_BASE_URL=/api \
  .
```

The frontend uses `API_BASE_URL` from `src/config/apiConfig.js`:
- In dev: `http://localhost:5000`
- In prod: `/api` (or overridden via `VITE_API_BASE_URL`)

### 2.5 Tag images with full ECR URIs

```bash
BACKEND_ECR_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/movie-manager-backend:$BACKEND_TAG
FRONTEND_ECR_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/movie-manager-frontend:$FRONTEND_TAG

docker tag movie-manager-backend:$BACKEND_TAG   $BACKEND_ECR_URI
docker tag movie-manager-frontend:$FRONTEND_TAG $FRONTEND_ECR_URI
```

### 2.6 Push images to ECR

```bash
docker push $BACKEND_ECR_URI
docker push $FRONTEND_ECR_URI
```

Optionally verify:
```bash
aws ecr describe-images \
  --repository-name movie-manager-backend \
  --region $AWS_REGION \
  --query 'imageDetails[].imageTags' \
  --output table

aws ecr describe-images \
  --repository-name movie-manager-frontend \
  --region $AWS_REGION \
  --query 'imageDetails[].imageTags' \
  --output table
```

## 3️⃣ Install AWS Load Balancer Controller via Bash Script

We use the `infra/addons/aws-lbc-cli.sh` script to automate:
- Associating IAM OIDC provider with EKS
- Ensuring the IAM policy (`infra/addons/iam-policy.json`)
- Creating the IAM role + Kubernetes ServiceAccount
- Installing / upgrading AWS Load Balancer Controller via Helm
- Ensuring IngressClass named `alb`
- (Optionally) deploying a sample Nginx Ingress

From the folder where `infra/addons/aws-lbc-cli.sh` & `infra/addons/iam-policy.json` exist:

```bash
cd scripts    # or wherever the script lives

chmod +x infra/addons/aws-lbc-cli.sh

# With sample Nginx app (for quick testing)
./infra/addons/aws-lbc-cli.sh --with-sample

# Or without sample app
./infra/addons/aws-lbc-cli.sh --no-sample
```

The script:
- Auto-detects VPC ID using terraform output when possible
- Uses the cluster name & region you pass via flags or defaults
- Waits for the `aws-load-balancer-controller` deployment to be ready

Useful checks:
```bash
kubectl get deploy aws-load-balancer-controller -n kube-system
kubectl get pods -n kube-system | grep aws-load-balancer-controller
kubectl get ingressclass
```
You should see an IngressClass called `alb`.

## 4️⃣ Deploy the Application to EKS

Assuming your Kubernetes manifests are in a `k8s/` directory.

### 4.1 MongoDB Deployment & Service

`k8s/mongo.yaml` (example):
- Deployment `mongo`
- Service `mongo` (ClusterIP, port 27017)

Apply:
```bash
kubectl apply -f k8s/mongo.yaml
kubectl get pods
kubectl get svc
```

### 4.2 Backend Deployment & Service

`k8s/movie-manager-backend.yaml` should use the ECR image and expose port 5000.

Apply:
```bash
kubectl apply -f k8s/movie-manager-backend.yaml
kubectl get deploy movie-manager-backend
kubectl get svc movie-manager-backend
```

### 4.3 Frontend Deployment & Service

`k8s/movie-manager-frontend.yaml` should use the ECR image and expose port 3000 (targetPort).

Apply:
```bash
kubectl apply -f k8s/movie-manager-frontend.yaml
kubectl get deploy movie-manager-frontend
kubectl get svc movie-manager-frontend
```

### 4.4 Ingress (ALB)

`k8s/movie-manager-ingress.yaml` (simplified):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: movie-manager-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: movie-manager-frontend
                port:
                  number: 80
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: movie-manager-backend
                port:
                  number: 5000
```

Apply:
```bash
kubectl apply -f k8s/movie-manager-ingress.yaml
kubectl get ingress
kubectl describe ingress movie-manager-ingress
```

After a few moments, the Ingress should show an ADDRESS field with the ALB DNS name.

## 5️⃣ Seed MongoDB with Movies

We seed the movies collection using `seed-movies.js` from inside the cluster.

### 5.1 Run a temporary Mongo shell pod

```bash
kubectl run mongo-shell \
  --image=mongo:latest \
  --restart=Never \
  --command -- sleep 3600
```

### 5.2 Copy the seed script

```bash
kubectl cp seed-movies.js mongo-shell:/seed-movies.js
```

### 5.3 Execute the seed script

```bash
kubectl exec -it mongo-shell -- \
  mongosh "mongodb://mongo:27017/movie_manager" /seed-movies.js
```

### 5.4 Verify the data

```bash
kubectl exec -it mongo-shell -- \
  mongosh "mongodb://mongo:27017/movie_manager" --eval "db.movies.countDocuments()"

kubectl exec -it mongo-shell -- \
  mongosh "mongodb://mongo:27017/movie_manager" --eval "db.movies.findOne()"
```

You should see 12 documents and a sample movie.
Delete the helper pod when done:
```bash
kubectl delete pod mongo-shell
```

## 6️⃣ End-to-End Check

### 6.1 Check backend from inside the cluster

Run a temporary curl pod:
```bash
kubectl run curl-test \
  --rm -it \
  --image=curlimages/curl:8.8.0 \
  --restart=Never -- \
  curl http://movie-manager-backend.default.svc.cluster.local:5000/api/movies
```
You should see a JSON array with 12 movies.

### 6.2 Access the app via ALB

Get the Ingress address:
```bash
kubectl get ingress movie-manager-ingress
```

Open the ADDRESS (e.g. `http://k8s-default-movieman-....elb.amazonaws.com`) in the browser. You should see:
- Movie Manager UI
- Posters loaded
- Data fetched from `/api/movies`

## 7️⃣ Useful Commands

**Scale pods:**
```bash
kubectl scale deploy/movie-manager-backend --replicas=3
kubectl scale deploy/movie-manager-frontend --replicas=3
```

**Update images:**
```bash
kubectl set image deploy/movie-manager-backend \
  backend=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/movie-manager-backend:new-tag

kubectl set image deploy/movie-manager-frontend \
  frontend=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/movie-manager-frontend:new-tag

kubectl rollout status deploy/movie-manager-backend
kubectl rollout status deploy/movie-manager-frontend
```

## 8️⃣ Tear Down (Cleanup)

To destroy everything:

**Delete Kubernetes resources:**
```bash
kubectl delete -f k8s/movie-manager-ingress.yaml
kubectl delete -f k8s/movie-manager-frontend.yaml
kubectl delete -f k8s/movie-manager-backend.yaml
kubectl delete -f k8s/mongo.yaml
```

**Destroy infrastructure with Terraform:**
```bash
cd infra/eks
terraform destroy
```

## 9️⃣ Networking Deep Dive

This section explains how networking works end-to-end:
from the user's browser on the Internet → through AWS → into the EKS cluster → down to the MongoDB pod.

---

### 9.1 AWS Networking – VPC & Subnets

Terraform provisions:

- A **VPC** (e.g. `10.0.0.0/16`)
- **Public subnets** across multiple AZs  
  → used by the **internet-facing ALB**
- **Private subnets** across multiple AZs  
  → used by the **EKS worker nodes**
- An **Internet Gateway** and public route table  
  → public subnets have a route `0.0.0.0/0` → Internet Gateway
- A **NAT Gateway** and private route table  
  → private subnets have a route `0.0.0.0/0` → NAT Gateway

Implications:

- The **ALB** is reachable from the Internet (lives in **public** subnets).
- The **EKS nodes & pods** live in **private** subnets and are *not* directly exposed.
- Nodes can still pull container images from ECR and talk to external services via the NAT Gateway.

---

### 9.2 Kubernetes Networking – Services & DNS

Inside the EKS cluster:

- Each **pod** gets an IP address from the VPC CIDR (AWS VPC CNI).
- We use **ClusterIP services** to expose pods internally:

  - `Service mongo`  
    - Type: `ClusterIP`  
    - Port: `27017` → MongoDB pod
  - `Service movie-manager-backend`  
    - Type: `ClusterIP`  
    - Port: `5000` → backend pods
  - `Service movie-manager-frontend`  
    - Type: `ClusterIP`  
    - Port: `80` → frontend pods (targetPort `3000`)

- **CoreDNS** provides internal DNS:
  - `mongo.default.svc.cluster.local` → `mongo` Service ClusterIP
  - `movie-manager-backend.default.svc.cluster.local` → backend Service
  - `movie-manager-frontend.default.svc.cluster.local` → frontend Service

The backend uses:

```text
MONGODB_URI = mongodb://mongo:27017/movie_manager
```
This relies entirely on Kubernetes DNS and does not hardcode any IPs.

### 9.3 ECR and Image Pulls from Private Subnets

Worker nodes live in private subnets and pull images from ECR via the NAT Gateway:

Container images are referenced by full ECR URI, e.g.:

```yaml
image: 163511166008.dkr.ecr.us-east-1.amazonaws.com/movie-manager-backend:eks-v1
```

When the pod starts, the kubelet on the node:
1. Makes an outbound connection to `*.dkr.ecr.us-east-1.amazonaws.com`
2. Flows through the NAT Gateway to the public Internet
3. Downloads the image and stores it locally on the node

No inbound connectivity from the Internet to the nodes is required; everything is outbound-only.

### 9.4 Ingress, AWS Load Balancer Controller & ALB

We use an `Ingress` object of class `alb` plus AWS Load Balancer Controller:

The `movie-manager-ingress` resource defines path-based routing:
- `/` → Service `movie-manager-frontend` (port 80)
- `/api` → Service `movie-manager-backend` (port 5000)

AWS Load Balancer Controller watches this Ingress and:
1. Creates an internet-facing ALB in the public subnets
2. Creates target groups of type `ip` for:
   - frontend pods
   - backend pods
3. Configures listeners & rules:
   - HTTP 80 listener
   - Rule `path=/` → frontend target group
   - Rule `path=/api` → backend target group

Traffic flow from the Internet:
1. User opens `http://<ALB-DNS>/` in the browser.
2. DNS resolves `<ALB-DNS>` to a public IP.
3. Request hits the ALB (in public subnets).
4. ALB forwards the request to the appropriate target group:
   - `/` → frontend pods
   - `/api` → backend pods
5. The backend pod calls MongoDB through the internal `mongo` service.
6. The MongoDB Service is ClusterIP only, so it is never exposed outside the cluster.

### 9.5 Why Frontend Uses /api Instead of Hardcoding a Host

The frontend uses a configuration like:

```javascript
// src/config/apiConfig.js
const DEFAULT_API_BASE_URL = import.meta.env.DEV
  ? "http://localhost:5000"
  : "/api";

export const API_BASE_URL =
  import.meta.env.VITE_API_BASE_URL || DEFAULT_API_BASE_URL;
```

In development:
- `API_BASE_URL` = `http://localhost:5000`
- Frontend talks to backend on your local machine.

In production (EKS):
- `API_BASE_URL` = `/api`
- Both frontend and backend are served behind the same ALB host.
- The Ingress does the path-based routing.

This keeps the networking simple:
- Single ALB DNS name.
- No CORS issues.
- Clear separation:
  - `/` → frontend
  - `/api` → backend.

### 9.6 Security Considerations (High-Level)

- **Only the ALB security group** is open to the Internet (e.g. TCP/80 or TCP/443).
- **Worker nodes**:
  - Live in private subnets.
  - Are reachable only from inside the VPC / via EKS control plane.
- **MongoDB**:
  - Exposed only via a ClusterIP Service.
  - Access is limited to pods inside the cluster.
- **ECR, S3, etc.**:
  - Accessed via outbound traffic through the NAT Gateway.

This design keeps:
- Public surface area minimal (only ALB is Internet-facing).
- App components isolated in private subnets with internal-only services.

## 🔚 Summary

- **Terraform**: builds the network, IAM, and EKS cluster.
- **Docker + ECR**: package backend & frontend and store them in a managed registry.
- **Bash scripting**: automates the AWS Load Balancer Controller setup.
- **Kubernetes**: defines the application and exposes it via ALB.
- **Mongo seeding**: fills the database.

This README documents the full flow from `terraform apply` → EKS up → images built & pushed → app deployed → movies visible through the public ALB URL.
