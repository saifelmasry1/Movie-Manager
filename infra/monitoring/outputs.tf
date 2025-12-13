output "grafana_alb_hostname" {
  value       = try(kubernetes_ingress_v1.grafana_alb.status[0].load_balancer[0].ingress[0].hostname, null)
  description = "ALB hostname for Grafana (may appear shortly after apply)"
}

output "grafana_secret_name" {
  value       = "kube-prometheus-stack-grafana"
  description = "Secret containing Grafana admin credentials"
}
