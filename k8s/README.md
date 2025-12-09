# Movie Manager – EKS Deployment Guide

This document describes how to deploy the Movie Manager application on an existing Amazon EKS cluster and expose it to the internet via AWS Application Load Balancer (ALB).

## Assumptions

Terraform has already created:
- **EKS cluster**: `depi-eks` (region: `us-east-1`)
- Worker nodes joined and `kubectl` can reach the cluster

ECR repositories exist for:
- `movie-manager-backend`
- `movie-manager-frontend`

## 0. Prerequisites

On your local machine (where you run the commands):
- `aws` CLI configured with the correct AWS account
- `kubectl`
- `eksctl`
- `helm`
- `docker`

Logged in to ECR:
```bash
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
```

## 1. Connect to the EKS cluster

After Terraform apply finishes:
```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name depi-eks
```

Verify:
```bash
kubectl get nodes
kubectl get pods -A
```
You should see your worker nodes in `Ready` state and the core system pods (`coredns`, `aws-node`, `kube-proxy`, …) running.

## 2. Install AWS Load Balancer Controller (ALB Controller)

All the ALB setup is automated using the bash script `aws-lbc-cli.sh`.

This script:
- Associates IAM OIDC provider with the cluster (idempotent).
- Ensures IAM policy `AWSLoadBalancerControllerIAMPolicy` exists using `iam-policy.json`.
- Creates/updates the IAM service account `kube-system/aws-load-balancer-controller` via `eksctl`.
- Installs/updates the Helm chart `eks/aws-load-balancer-controller`.
- Ensures the `IngressClass` named `alb` exists.

From the Terraform project directory:
```bash
chmod +x aws-lbc-cli.sh

# With sample NGINX test (optional)
./aws-lbc-cli.sh --with-sample

# Or without sample (for production)
./aws-lbc-cli.sh --no-sample
```

The script will:
- Auto-detect the VPC ID from Terraform output.
- Print progress for each step.
- Wait for the `aws-load-balancer-controller` deployment to roll out successfully.

You can confirm:
```bash
kubectl get deploy aws-load-balancer-controller -n kube-system
kubectl get pods -n kube-system | grep aws-load-balancer-controller
kubectl get ingressclass
```
You should see an ingress class called `alb`.

## 3. Build and push Docker images (Backend & Frontend)

### 3.1 Backend image

From `app/backend`:
```bash
docker build -t movie-manager-backend:eks-v1 .

docker tag movie-manager-backend:eks-v1 \
  <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/movie-manager-backend:eks-v1

docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/movie-manager-backend:eks-v1
```

### 3.2 Frontend image

The frontend is a Vite app. We build it with a base API URL of `/api` so that the browser calls the backend through the same ALB.

In `app/frontend/src/config/apiConfig.js`:
```javascript
// In dev: http://localhost:5000/api
// In prod (EKS/ALB): /api
const DEFAULT_API_BASE_URL = import.meta.env.DEV
  ? "http://localhost:5000/api"
  : "/api";

export const API_BASE_URL =
  import.meta.env.VITE_API_BASE_URL || DEFAULT_API_BASE_URL;
```

In `MoviesPage.jsx` and `MovieDetailsPage.jsx`, the requests use:
```javascript
// MoviesPage.jsx
const response = await axios.get(`${API_BASE_URL}/movies`);

// MovieDetailsPage.jsx
const response = await axios.get(`${API_BASE_URL}/movies/${id}`);
```

Build and push:
```bash
cd app/frontend

docker build -t movie-manager-frontend:eks-v1 \
  --build-arg VITE_API_BASE_URL=/api .

docker tag movie-manager-frontend:eks-v1 \
  <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/movie-manager-frontend:eks-v1

docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/movie-manager-frontend:eks-v1
```

## 4. Kubernetes manifests (MongoDB, Backend, Frontend, Ingress)

Apply the Kubernetes YAML files (names are examples – use your actual file names):
```bash
kubectl apply -f k8s/mongo-deployment.yaml
kubectl apply -f k8s/movie-manager-backend.yaml
kubectl apply -f k8s/movie-manager-frontend.yaml
kubectl apply -f k8s/movie-manager-ingress.yaml
```

### 4.1 MongoDB deployment

- Runs a single mongo pod.
- Exposes a ClusterIP service named `mongo` on port 27017.
- The backend uses this connection string:
  ```
  MONGODB_URI=mongodb://mongo:27017/movie_manager
  ```

### 4.2 Backend deployment & service

- **Deployment name**: `movie-manager-backend`
- **Container image**: `<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/movie-manager-backend:eks-v1`
- **Environment variables** (example):
  ```yaml
  env:
    - name: MONGODB_URI
      value: "mongodb://mongo:27017/movie_manager"
    - name: PORT
      value: "5000"
  ```
- **Service name**: `movie-manager-backend`
- **Type**: `ClusterIP`
- **Port**: 5000

### 4.3 Frontend deployment & service

- **Deployment name**: `movie-manager-frontend`
- **Container image**: `<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/movie-manager-frontend:eks-v1`
- **Service name**: `movie-manager-frontend`
- **Type**: `ClusterIP`
- **Port**: 80 (serves the built static files via `serve`)

### 4.4 Ingress (ALB)

`movie-manager-ingress.yaml`:
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
          # Frontend at "/"
          - path: /
            pathType: Prefix
            backend:
              service:
                name: movie-manager-frontend
                port:
                  number: 80
          # Backend API at "/api"
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: movie-manager-backend
                port:
                  number: 5000
```

This tells the AWS Load Balancer Controller to create an internet-facing ALB and route:
- `http://ALB-DNS/` → `frontend service`
- `http://ALB-DNS/api/...` → `backend service`

## 5. Seed the MongoDB database

The backend expects a `movies` collection with 12 documents.
We seed the data using `seed-movies.js` from inside the cluster.

### 5.1 Create a temporary mongo shell pod
```bash
kubectl run mongo-shell \
  --image=mongo:latest \
  --restart=Never \
  --command -- sleep 3600
```

### 5.2 Copy the seed script into the pod
```bash
kubectl cp seed-movies.js mongo-shell:/seed-movies.js
```

### 5.3 Run the seed script
```bash
kubectl exec -it mongo-shell -- \
  mongosh "mongodb://mongo:27017/movie_manager" /seed-movies.js
```

### 5.4 Verify that data exists
```bash
kubectl exec -it mongo-shell -- \
  mongosh "mongodb://mongo:27017/movie_manager" --eval "db.movies.countDocuments()"

kubectl exec -it mongo-shell -- \
  mongosh "mongodb://mongo:27017/movie_manager" --eval "db.movies.findOne()"
```
You should see 12 documents and one sample movie (e.g. “The Shawshank Redemption”).

After seeding, you can delete the helper pod:
```bash
kubectl delete pod mongo-shell
```

## 6. Validate backend connectivity inside the cluster

Run a temporary curl pod:
```bash
kubectl run curl-test \
  --rm -it \
  --image=curlimages/curl:8.8.0 \
  --restart=Never -- \
  curl http://movie-manager-backend.default.svc.cluster.local:5000/api/movies
```
You should get back a JSON array of 12 movies.

## 7. Access the app via AWS ALB

Get the Ingress and ALB DNS name:
```bash
kubectl get ingress movie-manager-ingress
```

Example output:
```
NAME                  CLASS   HOSTS   ADDRESS                                                PORTS   AGE
movie-manager-ingress alb     *       k8s-default-movieman-xxxxxxxxxx.us-east-1.elb.amazonaws.com   80      ...
```

Open this DNS name in your browser:  
`http://k8s-default-movieman-xxxxxxxxxx.us-east-1.elb.amazonaws.com/`

You should see:
- The Movie Manager UI.
- The movie posters for the 12 seeded movies.
- Clicking a movie card should open the movie details page (fetched from `/api/movies/:id`).

## 8. Useful commands

Update frontend image after new build:
```bash
kubectl set image deploy/movie-manager-frontend \
  frontend=<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/movie-manager-frontend:eks-v2

kubectl rollout status deploy/movie-manager-frontend
```

Update backend image:
```bash
kubectl set image deploy/movie-manager-backend \
  backend=<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/movie-manager-backend:eks-v2

kubectl rollout status deploy/movie-manager-backend
```

Delete app resources (keep cluster):
```bash
kubectl delete -f k8s/movie-manager-ingress.yaml
kubectl delete -f k8s/movie-manager-frontend.yaml
kubectl delete -f k8s/movie-manager-backend.yaml
kubectl delete -f k8s/mongo-deployment.yaml
```
