// infra/eks/jenkins-ec2.tf
// Ubuntu EC2 for Jenkins (bootstrapped via user-data).
// Created during the same `terraform apply` as the EKS cluster.

data "aws_region" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

variable "jenkins_instance_type" {
  type        = string
  description = "EC2 instance type for Jenkins"
  default     = "t3.medium"
}

variable "jenkins_root_volume_gb" {
  type        = number
  description = "Root volume size (GiB)"
  default     = 30
}

variable "jenkins_admin_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to access SSH(22) + Jenkins(8080)."
  default     = ["0.0.0.0/0"]
}

variable "jenkins_key_name" {
  type        = string
  description = "EC2 KeyPair name to attach to Jenkins instance (AWS EC2 KeyPairs in the same region)."
  default     = "azza"

  validation {
    condition     = length(trimspace(var.jenkins_key_name)) > 0
    error_message = "jenkins_key_name must not be empty."
  }
}

variable "jenkins_private_key_path" {
  type        = string
  description = "Local path to the PEM (ONLY used for SSH hint output). Not used by AWS."
  default     = "~/.ssh/azza.pem"
}

locals {
  jenkins_name = "jenkins-ec2"
}

resource "aws_security_group" "jenkins_sg" {
  name        = "${local.jenkins_name}-sg"
  description = "Jenkins EC2 SG (8080 + 22)"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    description = "Jenkins UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.jenkins_admin_cidrs
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.jenkins_admin_cidrs
  }

  egress {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.jenkins_name}-sg"
  }
}

data "aws_iam_policy_document" "jenkins_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jenkins_role" {
  name               = "${local.jenkins_name}-role"
  assume_role_policy = data.aws_iam_policy_document.jenkins_assume_role.json
}

data "aws_iam_policy_document" "jenkins_inline" {

  # Needed for: aws eks update-kubeconfig, kubectl auth, eksctl utils associate-iam-oidc-provider
  # Fixes your exact error: eks:DescribeClusterVersions
  statement {
    sid = "EKSRead"
    actions = [
      "eks:Describe*",
      "eks:List*",
      "eks:AccessKubernetesApi"
    ]
    resources = ["*"]
  }

  # Needed for: terraform in infra/monitoring (aws_eks_addon for ebs csi)
  statement {
    sid = "EKSAddons"
    actions = [
      "eks:CreateAddon",
      "eks:UpdateAddon",
      "eks:DeleteAddon",
      "eks:DescribeAddon",
      "eks:ListAddons",
      "eks:DescribeAddonVersions",
      "eks:TagResource",
      "eks:UntagResource"
    ]
    resources = ["*"]
  }

  # Needed for: eksctl IRSA + OIDC provider + policy creation (aws-lbc-cli.sh)
  statement {
    sid = "IAMForEksctlAndTerraform"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviders",
      "iam:TagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",

      "iam:CreatePolicy",
      "iam:GetPolicy",
      "iam:ListPolicies",
      "iam:DeletePolicy",
      "iam:ListInstanceProfilesForRole",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:CreateRole",
      "iam:GetRole",
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:PassRole",

      # ✅ لازم لتيرافورم بعد CreateRole
      "iam:ListRolePolicies",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
    ]
    resources = ["*"]
  }


  # Needed for: eksctl create iamserviceaccount (it uses CloudFormation stacks)
  statement {
    sid = "CloudFormationForEksctl"
    actions = [
      "cloudformation:CreateStack",
      "cloudformation:DeleteStack",
      "cloudformation:DescribeStacks",
      "cloudformation:DescribeStackEvents",
      "cloudformation:DescribeStackResources",
      "cloudformation:GetTemplate",
      "cloudformation:ListStacks",
      "cloudformation:ListStackResources",
      "cloudformation:UpdateStack",
      "cloudformation:UpdateTerminationProtection"
    ]
    resources = ["*"]
  }

  # Optional but helpful for tooling/diagnostics
  statement {
    sid = "EC2Describe"
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeRouteTables",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeNatGateways"
    ]
    resources = ["*"]
  }

  # ECR push/pull for images
  statement {
    sid = "ECRPushPull"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:DescribeRepositories",
      "ecr:CreateRepository",
      "ecr:DescribeImages",
      "ecr:BatchGetImage"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "STSIdentity"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "jenkins_inline" {
  name   = "${local.jenkins_name}-inline"
  role   = aws_iam_role.jenkins_role.id
  policy = data.aws_iam_policy_document.jenkins_inline.json
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "${local.jenkins_name}-profile"
  role = aws_iam_role.jenkins_role.name
}

resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.jenkins_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.jenkins_profile.name
  key_name                    = var.jenkins_key_name

  user_data                   = file("${path.module}/userdata/jenkins-ubuntu.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_size = var.jenkins_root_volume_gb
    volume_type = "gp3"
  }

  tags = {
    Name = local.jenkins_name
  }

  depends_on = [aws_eks_cluster.eks]
}

output "jenkins_instance_id" {
  value = aws_instance.jenkins.id
}

output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "jenkins_url" {
  value = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "jenkins_ssh_hint" {
  value = "ssh -o IdentitiesOnly=yes -i ${var.jenkins_private_key_path} ubuntu@${aws_instance.jenkins.public_ip}"
}

# Allow Jenkins EC2 SG to reach EKS API server SG on 443
resource "aws_security_group_rule" "jenkins_to_eks_api" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.jenkins_sg.id
  description              = "Allow Jenkins EC2 to reach EKS API server"
}
