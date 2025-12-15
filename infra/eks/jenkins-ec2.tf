// infra/eks/jenkins-ec2.tf
// Creates a dedicated Ubuntu EC2 instance for Jenkins (bootstrapped via user-data).
// It will be created during the SAME `terraform apply` that creates the EKS cluster + nodegroup.

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
  description = "CIDRs allowed to access SSH(22) + Jenkins(8080). Use your public IP/32."
  default     = ["0.0.0.0/0"]
}

variable "jenkins_key_name" {
  type        = string
  description = "Optional EC2 key pair name for SSH. Leave empty to rely on SSM (recommended)."
  default     = ""
}

locals {
  jenkins_name = "jenkins-ec2"
}

# Security Group for Jenkins
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
    description = "SSH (optional)"
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

# IAM role for Jenkins EC2 (instance profile)
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

# Minimal inline permissions: EKS describe + ECR push
data "aws_iam_policy_document" "jenkins_inline" {
  statement {
    sid     = "EKSDescribe"
    actions = ["eks:DescribeCluster"]
    resources = [
      aws_eks_cluster.eks.arn
    ]
  }

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
    sid     = "STSIdentity"
    actions = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "jenkins_inline" {
  name   = "${local.jenkins_name}-inline"
  role   = aws_iam_role.jenkins_role.id
  policy = data.aws_iam_policy_document.jenkins_inline.json
}

# (Optional but very useful) SSM access without SSH
resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
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

  iam_instance_profile = aws_iam_instance_profile.jenkins_profile.name

  key_name  = var.jenkins_key_name != "" ? var.jenkins_key_name : null
  user_data = file("${path.module}/userdata/jenkins-ubuntu.sh")

  root_block_device {
    volume_size = var.jenkins_root_volume_gb
    volume_type = "gp3"
  }

  tags = {
    Name = local.jenkins_name
  }

  # Create Jenkins EC2 alongside the cluster
  depends_on = [aws_eks_cluster.eks]
}

output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "jenkins_url" {
  value = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "jenkins_ssm_hint" {
  value = "aws ssm start-session --target ${aws_instance.jenkins.id} --region ${data.aws_region.current.name}"
}
