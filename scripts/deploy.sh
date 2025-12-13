#!/usr/bin/env bash
set -euo pipefail

run_tf () {
  local dir="$1"
  if ls "$dir"/*.tf >/dev/null 2>&1; then
    ( cd "$dir" && terraform init && terraform apply -auto-approve )
  else
    echo "==> skip $dir (no .tf files yet)"
  fi
}

run_tf infra/eks
run_tf infra/monitoring
