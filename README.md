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


### Recommended Grafana dashboards (important views + IDs)

> **Note:** `kube-prometheus-stack` usually provisions a bunch of Kubernetes/Prometheus dashboards automatically.
> In Grafana, go to **Dashboards → Browse** and you should already see folders like **Kubernetes** and **Prometheus**.

If you **don’t** see the dashboards you want (or you want cleaner “one-glance” views), you can import community dashboards from Grafana.com:

1) In Grafana: **Dashboards → New → Import**  
2) Paste the **Dashboard ID** below → **Load**  
3) Select your **Prometheus** data source → **Import**

#### Core Kubernetes + Prometheus (recommended)

- **Kubernetes cluster monitoring (via Prometheus)** — **ID: 315**  
  Good “big picture”: nodes, pods, namespaces, resource usage trends.

- **Node Exporter Full (node health & resources)** — **ID: 1860**  
  CPU/RAM/disk/network on every node (classic, widely used).

- **Kubernetes / Views / Global** — **ID: 15757**  
  High-level workload + cluster signals in one place.

- **Kubernetes / Views / Namespaces** — **ID: 15758**  
  Quickly spot “which namespace is misbehaving”.

- **Kubernetes / Views / Nodes** — **ID: 15759**  
  Node pressure, saturation, and per-node workload signals.

- **Kubernetes / Views / Pods** — **ID: 16511**  
  Pod-level restarts, CPU/RAM, and health per workload/pod.

- **Prometheus (server health/tsdb/scrapes)** — **ID: 19105**  
  Scrape health, rule evaluation, TSDB stats, and query performance.

#### Optional (AWS / Ingress angle)

- **AWS Load Balancer Controller** — **ID: 18319**  
  Useful *if* you are scraping the controller metrics into Prometheus (and you want a dashboard around it).

> Tip: don’t overdo dashboards. The “must-watch” signals for this project are usually:
> **Pod restarts**, **CPU/RAM pressure**, **HTTP 4xx/5xx**, and **Prometheus scrape errors**.

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

## 7) MongoDB seeding (using a temporary `mongo-shell` helper pod)

If you already have a full seed script (e.g. `seed-movies.js`) in your repo, the cleanest way to seed Mongo in-cluster is to run a temporary **Mongo shell pod**, copy the script into it, and execute it against the Mongo service.

### 7.1 Create a temporary `mongo-shell` pod

```bash
kubectl run mongo-shell \
  --image=mongo:latest \
  --restart=Never \
  --command -- sleep 3600
```

Wait until it’s running:

```bash
kubectl get pod mongo-shell -w
```

### 7.2 Put your seed script into a local file

Create `seed-movies.js` locally (example content):

```javascript
db.movies.deleteMany({}); // optional: wipe existing data

db.movies.insertMany([
  {
    title: "The Shawshank Redemption",
    year: 1994,
    genre: "Drama",
    rating: 9.3,
    posterUrl: "/images/shawshank.jpg",
    description: "Two imprisoned men bond over a number of years..."
  }
  // ... keep the rest of your 12 movies here ...
]);
```

### 7.3 Copy the script into the helper pod

```bash
kubectl cp seed-movies.js mongo-shell:/seed-movies.js
```

### 7.4 Execute the seed script (the important step)

> Replace `movie_manager` if your DB name differs.

```bash
kubectl exec -it mongo-shell -- \
  mongosh "mongodb://mongo:27017/movie_manager" /seed-movies.js
```

### 7.5 Verify the seeded data

Count documents:

```bash
kubectl exec -it mongo-shell -- \
  mongosh "mongodb://mongo:27017/movie_manager" --eval "db.movies.countDocuments()"
```

Fetch a sample document:

```bash
kubectl exec -it mongo-shell -- \
  mongosh "mongodb://mongo:27017/movie_manager" --eval "db.movies.findOne()"
```

Expected: **12 documents** and one sample movie.

### 7.6 Clean up

Delete the helper pod:

```bash
kubectl delete pod mongo-shell
```

### 7.7 End-to-End check from inside the cluster (optional but awesome)

Run a temporary curl pod to test the backend service DNS directly:

```bash
kubectl run curl-test \
  --rm -it \
  --image=curlimages/curl:8.8.0 \
  --restart=Never -- \
  curl http://movie-manager-backend.default.svc.cluster.local:5000/api/movies
```

Expected: a JSON array containing your seeded movies.


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