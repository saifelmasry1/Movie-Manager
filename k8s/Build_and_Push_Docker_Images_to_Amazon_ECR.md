# Build & Push Docker Images to Amazon ECR

This section explains how to build the backend and frontend Docker images and push them to Amazon ECR so that EKS can pull them.

## 0. Prerequisites

- AWS CLI installed and configured:
  ```bash
  aws configure
  ```
- Docker running on your machine
- You have the source code:
  ```
  app/
    backend/
      Dockerfile
    frontend/
      Dockerfile
  ```

Here I will use real examples:
- **AWS Account ID**: `163511166008`
- **Region**: `us-east-1`
- **Backend repo name**: `movie-manager-backend`
- **Frontend repo name**: `movie-manager-frontend`
- **Backend tag**: `eks-v1`
- **Frontend tag**: `eks-v2`

If these values are different for you, modify them before running the commands.

## 1. Create ECR Repositories (One time)

```bash
AWS_ACCOUNT_ID=163511166008
AWS_REGION=us-east-1

# Backend repo
aws ecr create-repository \
  --repository-name movie-manager-backend \
  --region $AWS_REGION

# Frontend repo
aws ecr create-repository \
  --repository-name movie-manager-frontend \
  --region $AWS_REGION
```

If the repo already exists, AWS will return an error that the repo exists; you can safely ignore it.

## 2. Login to ECR from Docker

```bash
AWS_ACCOUNT_ID=163511166008
AWS_REGION=us-east-1

aws ecr get-login-password --region $AWS_REGION \
  | docker login \
      --username AWS \
      --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

If the login is successful, you will see a message similar to:
`Login Succeeded`

## 3. Build Backend Image Locally

From the project folder:
```bash
cd app/backend
```

Build the image (example tag: `eks-v1`):
```bash
docker build -t movie-manager-backend:eks-v1 .
```

Verify that the image is built:
```bash
docker images | grep movie-manager-backend
```

## 4. Build Frontend Image Locally

From the frontend folder:
```bash
cd ../frontend
```

The frontend needs to know the API base URL at build time.
In EKS, we are operating such that:
- The frontend connects to the backend at: `/api`

So we pass `VITE_API_BASE_URL=/api`

```bash
docker build \
  -t movie-manager-frontend:eks-v2 \
  --build-arg VITE_API_BASE_URL=/api \
  .
```

Verify that the image exists:
```bash
docker images | grep movie-manager-frontend
```

## 5. Tag the Images with ECR URI

We identify the variables:

```bash
AWS_ACCOUNT_ID=163511166008
AWS_REGION=us-east-1

BACKEND_LOCAL_TAG=movie-manager-backend:eks-v1
FRONTEND_LOCAL_TAG=movie-manager-frontend:eks-v2

BACKEND_ECR_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/movie-manager-backend:eks-v1
FRONTEND_ECR_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/movie-manager-frontend:eks-v2
```

**Backend tagging**
```bash
docker tag $BACKEND_LOCAL_TAG $BACKEND_ECR_URI
```

**Frontend tagging**
```bash
docker tag $FRONTEND_LOCAL_TAG $FRONTEND_ECR_URI
```

You can see them:
```bash
docker images | grep movie-manager
```

You will find two tags for each image: one local and one ECR URI.

## 6. Push to ECR

**Backend**
```bash
docker push $BACKEND_ECR_URI
```

**Frontend**
```bash
docker push $FRONTEND_ECR_URI
```

Wait until every layer finishes uploading.

## 7. Verify Images on ECR

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

You should see the tags `eks-v1` and `eks-v2`.

## 8. Link Images to Kubernetes Manifests

In the Deployment files, use the same URIs:

**Backend – `movie-manager-backend.yaml`**
```yaml
containers:
  - name: backend
    image: 163511166008.dkr.ecr.us-east-1.amazonaws.com/movie-manager-backend:eks-v1
    ports:
      - containerPort: 5000
    env:
      - name: MONGODB_URI
        value: "mongodb://mongo:27017/movie_manager"
      - name: PORT
        value: "5000"
```

**Frontend – `movie-manager-frontend.yaml`**
```yaml
containers:
  - name: frontend
    image: 163511166008.dkr.ecr.us-east-1.amazonaws.com/movie-manager-frontend:eks-v2
    ports:
      - containerPort: 3000
```

If you change tags later (e.g. `eks-v3`), all you have to do is:
1. Build a new image with the new tag
2. Push it to ECR
3. Update the Deployment:

```bash
kubectl set image deploy/movie-manager-backend \
  backend=163511166008.dkr.ecr.us-east-1.amazonaws.com/movie-manager-backend:eks-v3

kubectl set image deploy/movie-manager-frontend \
  frontend=163511166008.dkr.ecr.us-east-1.amazonaws.com/movie-manager-frontend:eks-v3
```

Then monitor the rollout:
```bash
kubectl rollout status deploy/movie-manager-backend
kubectl rollout status deploy/movie-manager-frontend
```
