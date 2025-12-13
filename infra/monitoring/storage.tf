locals {
  ebs_csi_policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  oidc_issuer        = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
  oidc_no_https      = replace(local.oidc_issuer, "https://", "")
}

# NOTE: this data source requires the OIDC provider to already exist.
# If it fails, run once:
#   cd infra/eks && bash ../addons/aws-lbc-cli.sh --no-sample
data "aws_iam_openid_connect_provider" "this" {
  url = local.oidc_issuer
}

resource "aws_iam_role" "ebs_csi_irsa" {
  name = "${var.cluster_name}-ebs-csi-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Federated = data.aws_iam_openid_connect_provider.this.arn },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${local.oidc_no_https}:aud" = "sts.amazonaws.com",
          "${local.oidc_no_https}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi_irsa.name
  policy_arn = local.ebs_csi_policy_arn
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi_irsa.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = var.storage_class_name
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    fsType    = "ext4"
    encrypted = "true"
  }

  depends_on = [aws_eks_addon.ebs_csi]
}

# Force only gp3 to be default
resource "null_resource" "single_default_sc" {
  depends_on = [kubernetes_storage_class_v1.gp3]

  provisioner "local-exec" {
    command = <<EOT
set -e
aws eks update-kubeconfig --name "${var.cluster_name}" --region "${var.aws_region}" >/dev/null

for sc in $(kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{"\\n"}{end}'); do
  if [ "$sc" != "${var.storage_class_name}" ]; then
    kubectl patch sc "$sc" --type merge -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' >/dev/null 2>&1 || true
  fi
done

kubectl patch sc "${var.storage_class_name}" --type merge -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null
EOT
  }
}
