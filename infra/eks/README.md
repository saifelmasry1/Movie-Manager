# EKS Cluster & Jenkins Infrastructure

This directory uses **Terraform** to provision the core infrastructure for the project:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      terraform apply (infra/eks)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Creates the following AWS Resources:                                      │
│                                                                             │
│   ┌───────────────────────────────────────────────────────────────────┐    │
│   │                         VPC (10.0.0.0/16)                         │    │
│   │                                                                   │    │
│   │  ┌─────────────────────┐      ┌─────────────────────────────┐   │    │
│   │  │   Public Subnets    │      │     Private Subnets         │   │    │
│   │  │   10.0.1.0/24       │      │     10.0.101.0/24           │   │    │
│   │  │   10.0.2.0/24       │      │     10.0.102.0/24           │   │    │
│   │  │                     │      │                             │   │    │
│   │  │  ┌───────────────┐  │      │  ┌───────────────────────┐  │   │    │
│   │  │  │   Jenkins     │  │      │  │    EKS Node Group     │  │   │    │
│   │  │  │   EC2         │  │      │  │    (t3.medium x2)     │  │   │    │
│   │  │  │   t3.medium   │  │      │  │                       │  │   │    │
│   │  │  └───────────────┘  │      │  └───────────────────────┘  │   │    │
│   │  └─────────────────────┘      └─────────────────────────────┘   │    │
│   │                                                                   │    │
│   │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │    │
│   │  │ Internet Gateway│  │   NAT Gateway   │  │   Route Tables  │  │    │
│   │  └─────────────────┘  └─────────────────┘  └─────────────────┘  │    │
│   └───────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│   ┌───────────────────────────────────────────────────────────────────┐    │
│   │                      EKS Cluster (depi-eks)                       │    │
│   │                                                                   │    │
│   │   - Control Plane (AWS Managed)                                   │    │
│   │   - OIDC Provider (for IRSA)                                      │    │
│   │   - Node Group (2 nodes, min:1, max:3)                           │    │
│   └───────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│   ┌───────────────────────────────────────────────────────────────────┐    │
│   │                         IAM Resources                             │    │
│   │                                                                   │    │
│   │   - EKS Cluster Role           - Jenkins EC2 Instance Profile    │    │
│   │   - EKS Node Role              - Jenkins IAM Role (ECR, EKS)     │    │
│   │   - Security Groups            - aws-lbc-policy (for LBC)        │    │
│   └───────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

Outputs:
  → jenkins_url        = http://<PUBLIC_IP>:8080
  → jenkins_ssh_hint   = ssh -i ~/.ssh/key.pem ubuntu@<IP>
  → eks_cluster_name   = depi-eks
  → vpc_id             = vpc-xxxxxxxxx
```

**Components Created:**
1.  **Amazon EKS Cluster** (`depi-eks`): A managed Kubernetes cluster.
2.  **Jenkins Server**: An EC2 instance pre-installed with Jenkins for CI/CD.
3.  **Networking**: VPC, Subnets (Public/Private), Internet Gateway, NAT Gateway.
4.  **IAM Roles**: Necessary roles for EKS, Nodes, and Jenkins.

## 1. Prerequisites

- **AWS CLI v2**: Configured with valid credentials (`aws sts get-caller-identity`).
- **Terraform**: v1.0+.
- **SSH Key Pair**: You need an EC2 KeyPair (default: `azza`) in `us-east-1` for the Jenkins instance.
  - *If you use a different key name, update `terraform.tfvars`.*

## 2. Provisioning Infrastructure

Run the following from this directory (`infra/eks`):

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment
terraform plan -out tfplan

# Apply deployment
terraform apply tfplan
```

### Important Outputs
After a successful apply, Terraform will output:
- `jenkins_url`: The HTTP URL to access your Jenkins server (e.g., `http://X.X.X.X:8080`).
- `jenkins_ssh_hint`: The SSH command to access the Jenkins server.
- `eks_cluster_name`: The name of the created cluster (e.g., `depi-eks`).
- `vpc_id`: The ID of the created VPC.

## 3. Post-Provisioning Steps

### 3.1 Configure Local `kubectl`
Connect your local `kubectl` to the new cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name <CLUSTER_NAME>
```

### 3.2 Install AWS Load Balancer Controller (LBC)
The project includes a helper script to automate the installation of the AWS Load Balancer Controller. This is **required** for Ingress to work.

1.  Navigate to the addons directory:
    ```bash
    cd ../addons
    chmod +x aws-lbc-cli.sh
    ```

2.  Run the installation script:
    ```bash
    # This installs the LBC, creates IAM policies, and ServiceAccounts
    ./aws-lbc-cli.sh --no-sample
    ```

3.  Verify installation:
    ```bash
    kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
    ```

## 4. Architecture Notes

- **Jenkins Access**: The Jenkins Security Group allows access to port `8080` (Web UI) and `22` (SSH). By default, it is open to `0.0.0.0/0`, but you can restrict this via variables.
- **EKS Access**: The Jenkins IAM role is granted permission to access the EKS cluster to perform deployments (`kubectl`, `helm`).
- **State Files**: Terraform state is stored locally by default. For production, configure a remote backend (S3/DynamoDB).
