#!/usr/bin/env bash
set -Eeuo pipefail

trap 'rc=$?; echo "❌ فشل عند السطر $LINENO: $BASH_COMMAND (exit=$rc)" >&2' ERR

########################################
# User-configurable variables (Defaults)
########################################
# These values can be overridden by CLI arguments.

CLUSTER_NAME="depi-eks"
REGION="us-east-1"
VPC_ID=""              # Will be auto-detected from AWS EKS (preferred), then terraform output if empty
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
IAMSA_NAME="aws-load-balancer-controller"
NAMESPACE="kube-system"
DEPLOY_SAMPLE_NGINX="true"

# Chart settings (offline install via curl -> tgz)
CHART_VERSION="1.16.0"   # override via --chart-version
CHART_BASE_URL="https://aws.github.io/eks-charts"

########################################
# Function: Print usage and exit
########################################
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Deploys and configures the AWS Load Balancer Controller for EKS."
  echo ""
  echo "Options:"
  echo "  --cluster NAME         EKS cluster name (Default: ${CLUSTER_NAME})"
  echo "  --region REGION        AWS region (Default: ${REGION})"
  echo "  --vpc-id VPC_ID        VPC ID where ALBs will be created"
  echo "  --namespace NAME       Namespace for the controller (Default: ${NAMESPACE})"
  echo "  --chart-version VER    Helm chart version (Default: ${CHART_VERSION})"
  echo "  --with-sample          Deploy a sample NGINX app (Default)"
  echo "  --no-sample            Install controller only (no sample app)"
  echo "  -h, --help             Print this help message."
  exit 1
}

########################################
# Parse CLI arguments
########################################
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --vpc-id)
      VPC_ID="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --chart-version)
      CHART_VERSION="$2"
      shift 2
      ;;
    --with-sample)
      DEPLOY_SAMPLE_NGINX="true"
      shift
      ;;
    --no-sample)
      DEPLOY_SAMPLE_NGINX="false"
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      ;;
  esac
done

########################################
# Check required CLIs
########################################
for cmd in aws kubectl eksctl helm curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] '$cmd' is not installed or not in PATH. Please install it first."
    exit 1
  fi
done

########################################
# Try to auto-detect VPC_ID if empty
# Preferred: AWS EKS describe-cluster
# Fallback: terraform output (vpc_id)
########################################
if [[ -z "${VPC_ID}" ]]; then
  VPC_ID="$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" \
    --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || true)"
  if [[ -n "${VPC_ID}" && "${VPC_ID}" != "None" ]]; then
    echo "[INFO] Auto-detected VPC ID from EKS: ${VPC_ID}"
  else
    VPC_ID=""
  fi
fi

if [[ -z "${VPC_ID}" ]]; then
  if command -v terraform >/dev/null 2>&1; then
    if terraform output -raw vpc_id >/dev/null 2>&1; then
      VPC_ID="$(terraform output -raw vpc_id)"
      echo "[INFO] Auto-detected VPC ID from terraform output: ${VPC_ID}"
    fi
  fi
fi

# Validate VPC_ID
if [[ -z "${VPC_ID}" ]]; then
  echo "[ERROR] The VPC ID must be specified using --vpc-id or discoverable from EKS/terraform."
  usage
fi

if [[ ! "${VPC_ID}" =~ ^vpc-[0-9a-f]+$ ]]; then
  echo "[ERROR] Invalid VPC_ID='${VPC_ID}' (expected vpc-xxxxxxxxxxxxxxxxx)"
  exit 1
fi

########################################
# Configuration Summary
########################################
echo "=============================================="
echo "[CONFIG] Cluster:           ${CLUSTER_NAME}"
echo "[CONFIG] Region:            ${REGION}"
echo "[CONFIG] VPC ID:            ${VPC_ID}"
echo "[CONFIG] Namespace:         ${NAMESPACE}"
echo "[CONFIG] Policy name:       ${POLICY_NAME}"
echo "[CONFIG] IAM ServiceAccount ${IAMSA_NAME}"
echo "[CONFIG] Chart version:     ${CHART_VERSION}"
echo "[CONFIG] Deploy sample app: ${DEPLOY_SAMPLE_NGINX}"
echo "=============================================="
echo ""

########################################
# Get AWS Account ID
########################################
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "[INFO] Using AWS Account ID: ${ACCOUNT_ID}"
echo ""

########################################
# Step 1: Associate IAM OIDC provider with the cluster
########################################
echo "[STEP 1] Associating IAM OIDC provider with cluster (idempotent)..."

eksctl utils associate-iam-oidc-provider \
  --region "${REGION}" \
  --cluster "${CLUSTER_NAME}" \
  --approve

echo "[STEP 1] Done."
echo ""

########################################
# Step 2: Create or reuse IAM Policy for AWS Load Balancer Controller
########################################
echo "[STEP 2] Ensuring IAM policy '${POLICY_NAME}' exists..."

# Download iam-policy.json from official repo if not present locally
if [[ ! -f iam-policy.json ]]; then
  echo "[INFO] Downloading iam-policy.json from official AWS Load Balancer Controller repo..."
  curl -fsSL --retry 5 --retry-all-errors --connect-timeout 10 --max-time 120 \
    -o iam-policy.json \
    https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
fi

POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

# Check if policy exists; if yes, just reuse it (do NOT create new versions every run)
if aws iam get-policy --policy-arn "${POLICY_ARN}" >/dev/null 2>&1; then
  echo "[INFO] Policy already exists. Reusing existing policy ARN (no new version created)."
else
  echo "[INFO] Policy not found. Creating it now..."
  aws iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document file://iam-policy.json >/dev/null
fi

echo "[STEP 2] Policy ARN: ${POLICY_ARN}"
echo ""

########################################
# Step 3: Create/Update IAM ServiceAccount in kube-system (Robust check)
########################################
echo "[STEP 3] Creating/updating IAM service account '${IAMSA_NAME}' in namespace '${NAMESPACE}'..."

STACK_NAME="eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-${NAMESPACE}-${IAMSA_NAME}"

# Function: check if CloudFormation stack exists
stack_exists() {
  aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" >/dev/null 2>&1
}

# Function: disable termination protection if enabled
disable_termination_protection() {
  echo "[INFO] Disabling termination protection for stack '${STACK_NAME}' (if enabled)..."
  aws cloudformation update-termination-protection \
    --no-enable-termination-protection \
    --stack-name "${STACK_NAME}" >/dev/null 2>&1 || true
}

# Case 1: Stack exists
if stack_exists; then
  echo "[INFO] Found existing CloudFormation stack '${STACK_NAME}'."

  # Check if ServiceAccount exists in the current cluster
  if kubectl get sa "${IAMSA_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "[INFO] ServiceAccount '${IAMSA_NAME}' already exists in namespace '${NAMESPACE}'. Skipping eksctl create iamserviceaccount."
  else
    echo "[WARN] Stack '${STACK_NAME}' exists but ServiceAccount '${IAMSA_NAME}' is missing in cluster."
    echo "[INFO] Recreating the iamserviceaccount stack and ServiceAccount via eksctl to fix synchronization..."

    # Disable termination protection, then delete and recreate stack
    disable_termination_protection

    aws cloudformation delete-stack \
      --stack-name "${STACK_NAME}"

    echo "[INFO] Waiting for stack '${STACK_NAME}' to be deleted..."
    aws cloudformation wait stack-delete-complete \
      --stack-name "${STACK_NAME}"

    echo "[INFO] Recreating iamserviceaccount via eksctl..."
    eksctl create iamserviceaccount \
      --cluster "${CLUSTER_NAME}" \
      --namespace "${NAMESPACE}" \
      --name "${IAMSA_NAME}" \
      --attach-policy-arn "${POLICY_ARN}" \
      --override-existing-serviceaccounts \
      --region "${REGION}" \
      --approve
  fi
else
  # Case 2: No existing stack → normal creation
  echo "[INFO] No existing iamserviceaccount stack found. Creating a new one via eksctl..."
  eksctl create iamserviceaccount \
    --cluster "${CLUSTER_NAME}" \
    --namespace "${NAMESPACE}" \
    --name "${IAMSA_NAME}" \
    --attach-policy-arn "${POLICY_ARN}" \
    --override-existing-serviceaccounts \
    --region "${REGION}" \
    --approve
fi

echo "[STEP 3] IAM service account is ready."
echo ""

########################################
# Step 4: Install/Upgrade AWS Load Balancer Controller via Helm (OFFLINE via curl tgz)
########################################
echo "[STEP 4] Installing/Upgrading AWS Load Balancer Controller via Helm (offline tgz)..."

CHART_TGZ="/tmp/aws-load-balancer-controller-${CHART_VERSION}.tgz"
CHART_URL="${CHART_BASE_URL}/aws-load-balancer-controller-${CHART_VERSION}.tgz"

echo "[INFO] Downloading chart: ${CHART_URL}"
curl -fSL --retry 5 --retry-all-errors --connect-timeout 10 --max-time 180 \
  -o "${CHART_TGZ}" "${CHART_URL}"

if [[ ! -s "${CHART_TGZ}" ]]; then
  echo "[ERROR] Chart download failed or empty file: ${CHART_TGZ}"
  exit 1
fi

helm upgrade --install aws-load-balancer-controller "${CHART_TGZ}" \
  -n "${NAMESPACE}" \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name="${IAMSA_NAME}" \
  --set region="${REGION}" \
  --set vpcId="${VPC_ID}" \
  --wait --timeout 10m

echo "[STEP 4] Helm release 'aws-load-balancer-controller' installed/upgraded."
echo ""

########################################
# Step 5: Ensure IngressClass 'alb' exists
########################################
echo "[STEP 5] Ensuring IngressClass 'alb' exists..."

if ! kubectl get ingressclass alb >/dev/null 2>&1; then
  cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: alb
spec:
  controller: ingress.k8s.aws/alb
EOF
  echo "[INFO] IngressClass 'alb' created."
else
  echo "[INFO] IngressClass 'alb' already exists. Skipping."
fi

echo "[STEP 5] Done."
echo ""

########################################
# Step 6 (Optional): Deploy sample nginx + Ingress and print ALB DNS
########################################
if [[ "${DEPLOY_SAMPLE_NGINX}" == "true" ]]; then
  echo "[STEP 6] Deploying sample nginx app + Service + Ingress..."

  kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-nginx
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-nginx
  template:
    metadata:
      labels:
        app: my-nginx
    spec:
      containers:
        - name: nginx
          image: nginx:stable
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: my-nginx
  namespace: default
spec:
  selector:
    app: my-nginx
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-nginx
  namespace: default
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-nginx
                port:
                  number: 80
EOF

  echo "[STEP 6] Sample nginx resources created. Waiting for ALB DNS..."

  HOSTNAME=""
  for i in {1..30}; do
    HOSTNAME=$(kubectl get ingress my-nginx -n default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    if [[ -n "${HOSTNAME}" ]]; then
      echo "[INFO] Ingress hostname detected: ${HOSTNAME}"
      break
    fi
    echo "[INFO] Still waiting for ALB hostname... (${i}/30)"
    sleep 10
  done

  if [[ -z "${HOSTNAME}" ]]; then
    echo "[WARN] Timed out waiting for Ingress hostname. Please check:"
    echo "  - kubectl describe ingress my-nginx -n default"
    echo "  - kubectl logs -n ${NAMESPACE} deploy/aws-load-balancer-controller"
  else
    echo ""
    echo "[DONE] Sample nginx is exposed via AWS ALB."
    echo "[INFO] Try opening this URL in your browser:"
    echo "       http://${HOSTNAME}"
    echo ""
  fi
else
  echo "[STEP 6] DEPLOY_SAMPLE_NGINX is 'false' → skipping sample app deployment."
fi

echo "=============================================="
echo "[ALL DONE] AWS Load Balancer Controller setup complete."
echo "=============================================="
