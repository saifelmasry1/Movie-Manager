# EKS Cluster – AWS Load Balancer Controller Setup

This document describes how to start using the EKS cluster **after** `terraform apply` has finished and the cluster is up and running.

You will:

1. Configure `kubectl` access to the EKS cluster.
2. Install and configure the AWS Load Balancer Controller (ALB controller).
3. Optionally deploy a sample NGINX application behind an Application Load Balancer using `../addons/aws-lbc-cli.sh`.

---

## 1. Prerequisites

Make sure the following tools are installed on the machine you are using to manage the cluster:

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- `kubectl`
- `eksctl`
- `helm` (v3+)
- `bash`

AWS CLI must be configured with credentials that have permissions to manage:

- EKS
- IAM
- EC2
- CloudFormation

Example (check the active identity):

```bash
aws sts get-caller-identity
```

## 2. Assumptions and Terraform Outputs

We assume that `terraform apply` has already created:

- An EKS cluster (for example): `depi-eks`
- A VPC for the cluster (for example): `vpc-0bd776ab3b50e7f53`
- Public and private subnets
- A managed node group for the cluster

Typical Terraform outputs used later:

- `eks_cluster_name`
- `vpc_id`
- (optionally) `public_subnet_ids`, `private_subnet_ids`

You can adapt the example commands in this README to your own cluster name and VPC ID.

## 3. Configure kubectl for the EKS Cluster

Use the AWS CLI to update your local kubeconfig and add the EKS cluster context.

Example:

```bash
aws eks update-kubeconfig \
  --name depi-eks \
  --region us-east-1
```

Verify that you can communicate with the cluster:

```bash
kubectl get nodes
```

You should see your worker nodes in `Ready` state.

Also verify core system pods:

```bash
kubectl get pods -A
```

You should see pods such as:

- `coredns`
- `kube-proxy`
- `aws-node`

All (or most) should be in `Running` state.

## 4. AWS Load Balancer Controller Installation (via ../addons/aws-lbc-cli.sh)

The script `../addons/aws-lbc-cli.sh` automates the setup of the AWS Load Balancer Controller for EKS. It performs the following:

- Associates an IAM OIDC provider with the EKS cluster (IRSA).
- Ensures an IAM policy for the controller exists (using `../addons/iam-policy.json` or the official policy).
- Creates or updates an IAM ServiceAccount in `kube-system`.
- Installs or upgrades the AWS Load Balancer Controller Helm chart.
- Ensures an IngressClass named `alb` exists.
- Optionally deploys a sample NGINX application + Service + Ingress behind an ALB and prints its DNS.

### 4.1. Make the script executable

From the repo root (or wherever the script is placed):

```bash
chmod +x ../addons/aws-lbc-cli.sh
```

### 4.2. Basic usage (with defaults)

If the script has default values like:

- `CLUSTER_NAME="depi-eks"`
- `REGION="us-east-1"`
- `VPC_ID="vpc-0bd776ab3b50e7f53"`

you can simply run:

```bash
./../addons/aws-lbc-cli.sh --with-sample
```

or:

```bash
./../addons/aws-lbc-cli.sh --no-sample
```

### 4.3. CLI arguments

The script supports several arguments:

- `--cluster NAME`: EKS cluster name (e.g. `depi-eks`)
- `--region REGION`: AWS region (e.g. `us-east-1`)
- `--vpc-id VPC_ID`: VPC ID where ALBs should be created (e.g. `vpc-0bd776ab3b50e7f53`)
- `--namespace NAME`: Namespace for the controller (default: `kube-system`)
- `--policy-name NAME`: IAM policy name (default: `AWSLoadBalancerControllerIAMPolicy`)
- `--iam-sa-name NAME`: ServiceAccount name (default: `aws-load-balancer-controller`)
- `--with-sample`: Deploys a sample NGINX app + Service + Ingress and prints ALB DNS.
- `--no-sample`: Installs the controller only (no sample app).
- `-h, --help`: Prints usage.

**Example 1 – Install controller + sample app**

```bash
./../addons/aws-lbc-cli.sh \
  --cluster depi-eks \
  --region us-east-1 \
  --vpc-id vpc-0bd776ab3b50e7f53 \
  --with-sample
```

**Example 2 – Install controller only (no sample app)**

```bash
./../addons/aws-lbc-cli.sh \
  --cluster depi-eks \
  --region us-east-1 \
  --vpc-id vpc-0bd776ab3b50e7f53 \
  --no-sample
```

## 5. What the script does (high level)

When you run `../addons/aws-lbc-cli.sh`, it performs:

**OIDC Association**

```bash
eksctl utils associate-iam-oidc-provider \
  --region <REGION> \
  --cluster <CLUSTER_NAME> \
  --approve
```

**IAM Policy**

- Checks if an IAM policy named (e.g.) `AWSLoadBalancerControllerIAMPolicy` already exists.
- If not, it creates it using `../addons/iam-policy.json` (either from the repo or downloaded from the official AWS Load Balancer Controller documentation).
- If it exists, it reuses the existing policy ARN.

**IAM ServiceAccount**

Creates or updates a ServiceAccount in `kube-system` with an attached IAM role using IRSA:

```bash
eksctl create iamserviceaccount \
  --cluster <CLUSTER_NAME> \
  --namespace <NAMESPACE> \
  --name <IAMSA_NAME> \
  --attach-policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/<POLICY_NAME> \
  --override-existing-serviceaccounts \
  --region <REGION> \
  --approve
```

**AWS Load Balancer Controller Helm chart**

Installs or upgrades the Helm release:

```bash
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n <NAMESPACE> \
  --set clusterName=<CLUSTER_NAME> \
  --set serviceAccount.create=false \
  --set serviceAccount.name=<IAMSA_NAME> \
  --set region=<REGION> \
  --set vpcId=<VPC_ID>
```

**IngressClass alb**

Ensures that an IngressClass named `alb` exists with controller `ingress.k8s.aws/alb`.

**Sample NGINX app (if `--with-sample` is used)**

- Deploys a small NGINX Deployment + Service + Ingress in the default namespace.
- Waits for the ALB DNS to be assigned to the Ingress.
- Prints an HTTP URL that you can open in the browser to verify end-to-end traffic.

## 6. Verifying the AWS Load Balancer Controller

After running the script, verify that the controller is running:

```bash
kubectl get deploy aws-load-balancer-controller -n kube-system
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

You should see replicas in `Running` state.

## 7. Verifying the sample NGINX application (if `--with-sample`)

If you used `--with-sample`, the script will:

1. Deploy Deployment, Service, and Ingress named `my-nginx` in the default namespace.
2. Wait until the Ingress has an external hostname (the ALB DNS).
3. Print something like:

```text
[DONE] Sample nginx is exposed via AWS ALB.
[INFO] Try opening this URL in your browser:
       http://k8s-default-mynginx-xxxxxxxxxx.us-east-1.elb.amazonaws.com
```

You can also check manually:

```bash
kubectl get ingress my-nginx -n default
```

You should see a non-empty `ADDRESS` field (the ALB DNS name).

Open the printed URL in a browser. You should see the default NGINX welcome page.

## 8. Deploying your own application behind the ALB

Once the AWS Load Balancer Controller is installed, you can deploy your own applications using Kubernetes Ingress objects.

High-level requirements:

- Deployment for your app (pods).
- Service (usually ClusterIP) exposing the pods on a port (e.g. 80).
- Ingress with:
    - `spec.ingressClassName: alb`
    - Proper annotations for ALB behavior.
    - Backend pointing to your Service/port.

Example Ingress snippet:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
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
                name: my-app-service
                port:
                  number: 80
```

Apply your manifests:

```bash
kubectl apply -f my-app-deployment.yaml
kubectl apply -f my-app-service.yaml
kubectl apply -f my-app-ingress.yaml
```

Then:

```bash
kubectl get ingress my-app -n default
```

Use the `ADDRESS`/hostname to access your application via the AWS Application Load Balancer.

## 9. Cleaning up the sample (optional)

If you used `--with-sample` and want to remove the sample NGINX application later:

```bash
kubectl delete ingress my-nginx -n default
kubectl delete service my-nginx -n default
kubectl delete deployment my-nginx -n default
```

This does not remove the AWS Load Balancer Controller itself; only the sample app.

With these steps, you can go from “Terraform cluster is up” to “applications running behind an AWS Application Load Balancer on EKS” using a single automated script and standard Kubernetes manifests.
