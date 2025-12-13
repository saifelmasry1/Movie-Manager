#!/usr/bin/env bash
set -e
( cd infra/eks && terraform init && terraform apply -auto-approve )
( cd infra/monitoring && terraform init && terraform apply -auto-approve )
