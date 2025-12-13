variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "depi-eks"
}

variable "namespace" {
  type    = string
  default = "monitoring"
}

variable "storage_class_name" {
  type    = string
  default = "gp3"
}

variable "prometheus_size" {
  type    = string
  default = "20Gi"
}

variable "grafana_size" {
  type    = string
  default = "10Gi"
}

variable "kube_prometheus_stack_version" {
  type    = string
  default = "80.2.2"
}
