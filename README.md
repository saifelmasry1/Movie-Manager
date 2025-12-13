# Movie Manager on AWS EKS (Terraform + Kubernetes + Monitoring)

This repo deploys a simple **Movie Manager** app (Frontend + Backend + MongoDB) on **AWS EKS**, fronted by an **AWS ALB Ingress** (via AWS Load Balancer Controller), and adds **Monitoring** (Prometheus + Grafana) via **kube-prometheus-stack**.

The goal of this README is to be a **step-by-step runbook**: copy/paste commands, see what “good” looks like, and verify each layer is healthy.

---

## High-level architecture (routing + networks)

```text
                         ┌──────────────────────────────────────────────────┐
                         │                      AWS                         │
                         │                                                  │
Internet                 │   VPC                                             │
  │                      │   ┌───────────────┐     ┌─────────────────────┐  │
  │ HTTP :80             │   │ Public Subnets│     │ Private Subnets      │  │
  ▼                      │   │ (ALB lives)   │     │ (EKS Nodes live)     │  │
┌─────────────────┐     │   └───────┬───────┘     └─────────┬───────────┘  │
│  ALB (Ingress)  │◄────┤           │                         │              │
│ (AWS LBC)       │     │   Target Groups (IP mode)           │              │
│ Listener :80    │─────┤──────────────┬──────────────────────┘              │
└───────┬─────────┘     │              │                                     │
        │               │              │                                     │
        │ Path Rules    │              │                                     │
        │               │              │                                     │
        │  "/"          │              │                                     │
        ▼               │              ▼                                     │
  ┌───────────────┐     │      ┌─────────────────────────┐                   │
  │ Frontend TG   │─────┼─────►│ Service: movie-manager- │                   │
  │ (to Pods IPs) │     │      │ frontend (ClusterIP:80) │                   │
  └───────────────┘     │      └─────────────┬───────────┘                   │
                        │                    │                               │
                        │                    ▼                               │
                        │          ┌───────────────────┐                     │
                        │          │ Frontend Pods     │                     │
                        │          │ serve static UI   │                     │
                        │          │ (container :3000) │                     │
                        │          └───────────────────┘                     │
                        │                                                    │
                        │  "/api/*"  and "/images/*"                         │
                        ▼                                                    │
                  ┌───────────────┐                                          │
                  │ Backend TG    │─────────────────────────────────────────┐ │
                  │ (to Pods IPs) │                                         │ │
                  └───────────────┘                                         │ │
                                                                            ▼ ▼
                                                                ┌─────────────────────────┐
                                                                │ Service: movie-manager- │
                                                                │ backend (ClusterIP:5000)│
                                                                └─────────────┬───────────┘
                                                                              │
                                                                              ▼
                                                                    ┌───────────────────┐
                                                                    │ Backend Pods      │
                                                                    │ Express API       │
                                                                    │ :5000             │
                                                                    └─────────┬─────────┘
                                                                              │
                                                                              │ (ClusterIP DNS)
                                                                              ▼
                                                                    ┌───────────────────┐
                                                                    │ Service: mongo    │
                                                                    │ (ClusterIP:27017) │
                                                                    └─────────┬─────────┘
                                                                              │
                                                                              ▼
                                                                    ┌───────────────────┐
                                                                    │ Mongo Pod         │
                                                                    │ :27017            │
                                                                    └───────────────────┘


Monitoring is a separate namespace + separate ALB:

Internet → ALB (Ingress in monitoring ns) → Service grafana → Grafana Pods
```

**Key routing idea:** the frontend uses **relative URLs** in production:
- API: `/api/...`
- Images: `/images/...`

So the browser calls the same ALB hostname, and the Ingress routes to backend.

---

## Repo layout (important folders)

Typical layout you’ll use while following this README:

- `infra/eks/` — Terraform for EKS + core addons (example: EBS CSI, LBC prerequisites, IAM policy, …)
- `infra/monitoring/` — Terraform that installs kube-prometheus-stack + Grafana ALB Ingress
- `k8s/` — Kubernetes manifests: `mongo.yaml`, `movie-manager-backend.yaml`, `movie-manager-frontend.yaml`, `movie-manager-ingress.yaml` (names may vary)
- `app/frontend/` — Vite/React frontend + Dockerfile
- `app/backend/` — Backend + Dockerfile

(If your repo differs slightly, adjust paths, but the workflow stays the same.)

---

## 0) Prerequisites

Tools on your machine:

- AWS CLI v2 authenticated (`aws sts get-caller-identity` should work)
- Terraform
- kubectl
- Docker
- (Optional) Helm

AWS variables used in commands:

```bash
export ACCOUNT_ID="<YOUR_AWS_ACCOUNT_ID>"
export AWS_REGION="us-east-1"
```

---

## 1) Terraform: Provision EKS (infra/eks)

> Run this from the repo root.

```bash
cd infra/eks
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out tfplan
terraform apply tfplan
```

### Configure kubectl for the new cluster

Replace `<CLUSTER_NAME>` with whatever your Terraform creates.

```bash
aws eks update-kubeconfig --region "$AWS_REGION" --name "<CLUSTER_NAME>"
kubectl get nodes -o wide
```

**Good sign:** you see nodes in `Ready`.

---

## 2) Terraform: Install Monitoring (infra/monitoring)

```bash
cd ../../infra/monitoring
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out tfplan
terraform apply tfplan
```

### Get Grafana URL

If monitoring creates an Ingress called `grafana-alb`:

```bash
kubectl get ingress -n monitoring
kubectl get ingress -n monitoring grafana-alb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'
```

### Get Grafana admin password (kube-prometheus-stack)

Common secret name pattern (adjust if your release name differs):

```bash
kubectl get secret -n monitoring | grep -i grafana
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Login:
- user: `admin`
- password: (from the command above)

---

## 3) Deploy Movie Manager to the cluster (k8s)

From repo root:

```bash
kubectl apply -f k8s/mongo.yaml
kubectl apply -f k8s/movie-manager-backend.yaml
kubectl apply -f k8s/movie-manager-frontend.yaml
kubectl apply -f k8s/movie-manager-ingress.yaml   # if you have it
```

Wait for rollouts:

```bash
kubectl rollout status deploy/mongo --timeout=5m || true
kubectl rollout status deploy/movie-manager-backend --timeout=5m
kubectl rollout status deploy/movie-manager-frontend --timeout=5m
```

Check resources:

```bash
kubectl get deploy,pods,svc,ingress
kubectl get events --sort-by=.lastTimestamp | tail -n 30
```

### Get the Movie Manager ALB DNS

```bash
ALB=$(kubectl get ingress movie-manager-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "$ALB"
```

---

## 4) Build & Push Docker Images to ECR

### 4.1 Login to ECR

```bash
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin \
  "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
```

> If the ECR repo doesn’t exist yet, create it:
```bash
aws ecr describe-repositories --repository-names movie-manager-backend --region "$AWS_REGION" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name movie-manager-backend --region "$AWS_REGION"

aws ecr describe-repositories --repository-names movie-manager-frontend --region "$AWS_REGION" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name movie-manager-frontend --region "$AWS_REGION"
```

---

## 5) Practical example: Backend Build & Push (ECR) + Deploy + Verify

This section mirrors the “frontend style” flow: **Build → Push → Update → Verify**.

### 5.1 Choose a tag

Use immutable tags when you can (best practice):

```bash
TAG=eks-backend-$(date +%Y%m%d%H%M)
echo "$TAG"
```

### 5.2 Build backend image

Assuming your backend Dockerfile is at `app/backend/Dockerfile`:

```bash
docker build \
  -t "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/movie-manager-backend:$TAG" \
  -f app/backend/Dockerfile app/backend
```

**If your cluster nodes are x86_64 and you build on Apple Silicon**, add:
```bash
# docker build --platform linux/amd64 ...
```

### 5.3 Push backend image

```bash
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/movie-manager-backend:$TAG"
```

### 5.4 Update deployment on the cluster

#### Option A (recommended): set the deployment image to the new immutable tag

```bash
kubectl set image deploy/movie-manager-backend \
  backend="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/movie-manager-backend:$TAG"

kubectl rollout status deploy/movie-manager-backend --timeout=5m
```

#### Option B (lab/demo): keep `:latest` + `imagePullPolicy: Always`

If your manifest is using `:latest` and you push a new `:latest`, you must restart pods to force a pull:

```bash
kubectl rollout restart deploy/movie-manager-backend
kubectl rollout status deploy/movie-manager-backend --timeout=5m
```

Check what the cluster is running:

```bash
kubectl get deploy movie-manager-backend -o jsonpath='{.spec.template.spec.containers[0].image}{" | "}{.spec.template.spec.containers[0].imagePullPolicy}{"\n"}'
```

---

## 6) Verification (the most important part)

### 6.1 Kubernetes health

```bash
kubectl get deploy,pods,svc,ingress
kubectl get events --sort-by=.lastTimestamp | tail -n 20
kubectl rollout status deploy/movie-manager-backend --timeout=2m
kubectl rollout status deploy/movie-manager-frontend --timeout=2m
```

### 6.2 External routing (ALB + Ingress)

```bash
ALB=$(kubectl get ingress movie-manager-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Frontend should be 200
curl -s -o /dev/null -w "frontend=%{http_code}\n" "http://$ALB/"

# Backend should be 200 and return JSON
curl -s -o /dev/null -w "api=%{http_code}\n" "http://$ALB/api/movies"
curl -s "http://$ALB/api/movies" | head -c 200; echo
```

### 6.3 Frontend build sanity (no localhost in production JS)

Get the JS bundle path and search inside it:

```bash
JS=$(curl -s "http://$ALB/" | grep -oE 'src="[^"]+\.js"' | head -n 1 | cut -d'"' -f2)
echo "JS=$JS"

# Should NOT show localhost:5000
curl -s --compressed "http://$ALB$JS" | grep -Eo 'localhost:5000|http://localhost:5000/api' | head || true

# It IS okay to see "/api"
curl -s --compressed "http://$ALB$JS" | grep -Eo '"/api"' | head
```

### 6.4 Check logs quickly (optional but useful)

```bash
kubectl logs deploy/movie-manager-backend --tail=80
kubectl logs deploy/movie-manager-frontend --tail=80
```

---

## 7) MongoDB seeding (practical)

Sometimes you want to wipe + re-seed the `movies` collection.

### 7.1 Find Mongo pod

Try the label first:

```bash
kubectl get pods -l app=mongo
```

If your manifest doesn’t use that label, just grab it by name:

```bash
kubectl get pods | grep -i mongo
MPOD=$(kubectl get pods | awk '/^mongo-/{print $1; exit}')
echo "$MPOD"
```

### 7.2 Identify which DB name the backend uses (recommended)

Your backend deployment usually has `MONGO_URI` or similar env var:

```bash
kubectl get deploy movie-manager-backend -o yaml | grep -nE "MONGO|mongo"
```

Look for something like:
- `mongodb://mongo:27017/movie_manager`
- `mongodb://mongo:27017/moviemanager`

That last part is the **database name**.

### 7.3 Seed using mongosh (works on the official mongo image)

Replace `movie_manager` with your DB name if different:

```bash
DB_NAME="movie_manager"

kubectl exec -i "$MPOD" -- mongosh --quiet <<EOF
use ${DB_NAME}

db.movies.deleteMany({})

db.movies.insertMany([
  {
    title: "The Shawshank Redemption",
    year: 1994,
    genre: "Drama",
    rating: 9.3,
    posterUrl: "/images/shawshank.jpg",
    description: "Two imprisoned men bond over a number of years..."
  },
  {
    title: "The Godfather",
    year: 1972,
    genre: "Crime",
    rating: 9.2,
    posterUrl: "/images/godfather.jpg",
    description: "The aging patriarch of an organized crime dynasty..."
  },
  {
    title: "Inception",
    year: 2010,
    genre: "Sci-Fi",
    rating: 8.8,
    posterUrl: "/images/inception.jpg",
    description: "A thief who steals corporate secrets through dream-sharing..."
  }
])

db.movies.countDocuments()
EOF
```

**Good sign:** the last line prints `3`.

### 7.4 Verify the API after seeding

```bash
ALB=$(kubectl get ingress movie-manager-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s "http://$ALB/api/movies" | head -c 300; echo
```

---

## 8) Notes on `:latest` and `imagePullPolicy`

For learning/labs, it’s convenient to use:

- `image: ...:latest`
- `imagePullPolicy: Always`

Then after pushing a new `:latest`, do:

```bash
kubectl rollout restart deploy/movie-manager-frontend
kubectl rollout restart deploy/movie-manager-backend
```

For real production, prefer **immutable tags** (like the timestamp tags above) to avoid “it works on my cluster” mysteries.

---

## 9) Troubleshooting checklist

- **Ingress not getting an address**
  ```bash
  kubectl describe ingress movie-manager-ingress
  kubectl get pods -n kube-system | grep -i load-balancer
  ```

- **502/504 from ALB**
  - Check service ports match container ports
  - Check pods are Ready
  ```bash
  kubectl get endpoints movie-manager-backend
  kubectl describe pod <backend-pod>
  kubectl logs <backend-pod>
  ```

- **Frontend loads but API calls fail**
  - Verify your bundle uses `/api`, not `localhost`
  - Verify Ingress routes `/api/*` to backend
  ```bash
  kubectl get ingress movie-manager-ingress -o yaml | sed -n '1,200p'
  ```

- **Posters/images not loading**
  - If poster URLs look like `/images/...`, ensure Ingress also routes `/images/*` to backend.

---

## 10) Quick “everything is healthy” command set

```bash
kubectl get deploy,pods,svc,ingress
kubectl get events --sort-by=.lastTimestamp | tail -n 15

ALB=$(kubectl get ingress movie-manager-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s -o /dev/null -w "frontend=%{http_code}\n" "http://$ALB/"
curl -s -o /dev/null -w "api=%{http_code}\n" "http://$ALB/api/movies"
```

## MongoDB Persistence & Seeding (Production-Ready)

This project uses **MongoDB with persistent storage** backed by **AWS EBS (gp3 via the EBS CSI Driver)**.
Database seeding is implemented in a **repeatable and declarative** way using a Kubernetes Job.

---

### 1. MongoDB Persistent Storage (PVC)

MongoDB is deployed with the following constraints:

- **Single replica**
- **Recreate deployment strategy**
- **PersistentVolumeClaim mounted at `/data/db`**

This design guarantees:
- Only one MongoDB process writes to the volume
- Data survives pod restarts and rescheduling
- Safe usage of a single EBS volume

#### Apply MongoDB PVC and Deployment

```bash
kubectl apply -f k8s/mongo-pvc.yaml
kubectl apply -f k8s/mongo.yaml
```

Verify storage and pod state:

```bash
kubectl get pvc,pv | grep mongo
kubectl get pods -l app=mongo
```

Expected:
- PVC status: `Bound`
- Mongo pod: `Running`

---

### 2. MongoDB Seeding (Kubernetes Job)

Instead of manual `kubectl exec` seeding, MongoDB is populated using:

- **ConfigMap** → stores the seed JavaScript
- **Job** → runs `mongosh`, inserts data, and exits

This makes seeding **repeatable**, **auditable**, and **safe to rerun**.

#### Seed Manifests

- `k8s/mongo-seed-configmap.yaml`
- `k8s/mongo-seed-job.yaml`

#### Apply Seed Resources

```bash
kubectl apply -f k8s/mongo-seed-configmap.yaml
kubectl apply -f k8s/mongo-seed-job.yaml
```

Check job status and logs:

```bash
kubectl get jobs
kubectl logs job/mongo-seed-movies
```

Expected output:

```
Seeding Mongo at: mongodb://mongo:27017/movie_manager
Done.
```

> The seed script starts with `db.movies.deleteMany({})`,
> which makes the job **idempotent** and safe to re-run.

---

### 3. Verify MongoDB Data

Run a temporary Mongo shell pod:

```bash
kubectl run mongo-check \
  --rm -it \
  --image=mongo:7 \
  --restart=Never -- \
  mongosh "mongodb://mongo:27017/movie_manager" \
  --eval "db.movies.countDocuments()"
```

Expected output:

```
12
```

Verify a sample document:

```bash
kubectl run mongo-check \
  --rm -it \
  --image=mongo:7 \
  --restart=Never -- \
  mongosh "mongodb://mongo:27017/movie_manager" \
  --eval "db.movies.findOne()"
```

---

### 4. Backend End-to-End Verification (Inside the Cluster)

Verify backend connectivity to MongoDB:

```bash
kubectl run curl-test \
  --rm -it \
  --image=curlimages/curl:8.8.0 \
  --restart=Never -- \
  curl http://movie-manager-backend.default.svc.cluster.local:5000/api/movies
```

Expected:
- HTTP 200
- JSON array with **12 movies**

---

### 5. MongoDB Restart Safety Check

Restart MongoDB and verify data persistence:

```bash
kubectl rollout restart deploy/mongo
kubectl rollout status deploy/mongo
```

Re-check data:

```bash
kubectl run mongo-check \
  --rm -it \
  --image=mongo:7 \
  --restart=Never -- \
  mongosh "mongodb://mongo:27017/movie_manager" \
  --eval "db.movies.countDocuments()"
```

Expected:

```
12
```

✅ Confirms that PVC-backed storage is working correctly.

---

### 6. Design Notes & Future Improvements

- MongoDB runs as **single replica** to safely use one PVC
- For high availability, migrate to:
  - MongoDB ReplicaSet
  - StatefulSet
  - One PVC per replica
- The seed Job can be:
  - Re-run manually
  - Integrated into CI/CD
  - Converted into a Helm hook

---
