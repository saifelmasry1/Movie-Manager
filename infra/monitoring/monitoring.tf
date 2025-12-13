resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = var.namespace
  }
}

locals {
  release_name = "kube-prometheus-stack"
  grafana_svc  = "${local.release_name}-grafana"
}

resource "helm_release" "kps" {
  name      = local.release_name
  namespace = kubernetes_namespace_v1.monitoring.metadata[0].name

  # OCI (بدل https://prometheus-community.github.io/helm-charts)
  repository = "oci://ghcr.io/prometheus-community/charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_version

  values = [
    templatefile("${path.module}/values-kps.yaml", {
      storage_class   = var.storage_class_name
      prometheus_size = var.prometheus_size
      grafana_size    = var.grafana_size
    })
  ]

  timeout = 900
  atomic  = true

  depends_on = [
    null_resource.single_default_sc,
    aws_eks_addon.ebs_csi
  ]
}

resource "null_resource" "wait_for_lbc" {
  provisioner "local-exec" {
    command = <<EOT
set -e
aws eks update-kubeconfig --name "${var.cluster_name}" --region "${var.aws_region}" >/dev/null

kubectl -n kube-system get deploy/aws-load-balancer-controller >/dev/null 2>&1 || \
  (echo "ERROR: AWS Load Balancer Controller not found. Run: cd infra/eks && bash ../addons/aws-lbc-cli.sh --no-sample" && exit 1)

kubectl -n kube-system rollout status deploy/aws-load-balancer-controller --timeout=10m
kubectl get ingressclass alb >/dev/null 2>&1 || \
  (echo "ERROR: IngressClass 'alb' not found. Re-run your LBC script." && exit 1)
EOT
  }
}

resource "kubernetes_ingress_v1" "grafana_alb" {
  metadata {
    name      = "grafana-alb"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name

    annotations = {
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\":80}]"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/login"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = local.grafana_svc
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.kps,
    null_resource.wait_for_lbc
  ]
}
