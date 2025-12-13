#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
VPC_ID="${VPC_ID:-}"

GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[0;33m"; NC="\033[0m"
ok()   { echo -e "${GREEN}OK${NC}   - $*"; }
bad()  { echo -e "${RED}NOT OK${NC} - $*"; }
warn() { echo -e "${YELLOW}WARN${NC} - $*"; }

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need_cmd aws
need_cmd kubectl

infer_cluster_name() {
  local ctx
  ctx="$(kubectl config current-context 2>/dev/null || true)"
  [[ "$ctx" == *"cluster/"* ]] && echo "${ctx##*/}" && return 0
  return 1
}

infer_vpc_id_from_cluster() {
  local name="${1:?cluster name required}"
  aws eks describe-cluster --region "$REGION" --name "$name" \
    --query "cluster.resourcesVpcConfig.vpcId" --output text 2>/dev/null || true
}

# Infer CLUSTER_NAME
if [[ -z "${CLUSTER_NAME}" ]]; then
  if CLUSTER_NAME="$(infer_cluster_name)"; then
    warn "CLUSTER_NAME not set; inferred: ${CLUSTER_NAME}"
  else
    warn "CLUSTER_NAME not set and couldn't infer."
  fi
fi

# Infer VPC_ID if possible
if [[ -z "${VPC_ID}" && -n "${CLUSTER_NAME}" ]]; then
  VPC_ID="$(infer_vpc_id_from_cluster "$CLUSTER_NAME")"
  if [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]]; then
    warn "VPC_ID not set; inferred from EKS: ${VPC_ID}"
  else
    VPC_ID=""
    warn "Couldn't infer VPC_ID from EKS. Set VPC_ID manually if cluster already deleted."
  fi
fi

echo "=============================="
echo "Pre-Destroy Checks"
echo "REGION       = ${REGION}"
echo "CLUSTER_NAME = ${CLUSTER_NAME:-<unset>}"
echo "VPC_ID       = ${VPC_ID:-<unset>}"
echo "Kube context = $(kubectl config current-context 2>/dev/null || echo '<unknown>')"
echo "=============================="
echo

FAIL=0
KUBE_OK=0
AWS_OK=0

# ---------- K8s reachability ----------
if kubectl cluster-info >/dev/null 2>&1; then
  ok "kubectl can reach cluster"
  KUBE_OK=1
else
  bad "kubectl cannot reach cluster (kubeconfig/network). K8s checks will be skipped."
  FAIL=1
fi

# Helpers (K8s)
k8s_list_ingress() {
  kubectl get ingress -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null || true
}
k8s_list_tgb() {
  kubectl get targetgroupbinding -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null || true
}
k8s_list_lb_svcs() {
  kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null || true
}
count_lines() { sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '; }

echo
echo "== Kubernetes checks =="

if [[ "$KUBE_OK" -eq 1 ]]; then
  ing_list="$(k8s_list_ingress)"
  ing_count="$(printf "%s" "$ing_list" | count_lines)"
  if [[ "$ing_count" -eq 0 ]]; then ok "No Ingress resources"; else bad "Ingress still exists: $ing_count"; echo "$ing_list"; FAIL=1; fi

  if kubectl get crd targetgroupbindings.elbv2.k8s.aws >/dev/null 2>&1; then
    tgb_list="$(k8s_list_tgb)"
    tgb_count="$(printf "%s" "$tgb_list" | count_lines)"
    if [[ "$tgb_count" -eq 0 ]]; then ok "No TargetGroupBinding resources"; else bad "TargetGroupBinding still exists: $tgb_count"; echo "$tgb_list"; FAIL=1; fi
  else
    ok "TargetGroupBinding CRD not present (skipping)"
  fi

  lbsvc_list="$(k8s_list_lb_svcs)"
  lbsvc_count="$(printf "%s" "$lbsvc_list" | count_lines)"
  if [[ "$lbsvc_count" -eq 0 ]]; then ok "No Services of type LoadBalancer"; else bad "LoadBalancer Services still exist: $lbsvc_count"; echo "$lbsvc_list"; FAIL=1; fi
else
  warn "Skipping K8s resource checks because cluster is unreachable."
fi

# ---------- AWS checks ----------
echo
echo "== AWS checks =="

if aws sts get-caller-identity >/dev/null 2>&1; then
  ok "AWS CLI authenticated"
  AWS_OK=1
else
  bad "AWS CLI not authenticated / no permission"
  FAIL=1
fi

aws_query_or_fail() {
  # usage: aws_query_or_fail "<desc>" aws .....
  local desc="$1"; shift
  local out
  if out="$("$@" 2>/dev/null)"; then
    printf "%s" "$out"
    return 0
  else
    bad "$desc (AWS call failed)"
    FAIL=1
    return 1
  fi
}

# LBs by name prefix (k8s-)
lb_prefix_out="$(aws_query_or_fail "Describe ELBv2 load balancers" aws elbv2 describe-load-balancers --region "$REGION" \
  --query "LoadBalancers[?starts_with(LoadBalancerName,'k8s-')].[LoadBalancerName,Type,State.Code,DNSName]" --output text || true)"

if [[ -z "${lb_prefix_out// }" ]]; then
  ok "No ELBv2 load balancers with prefix 'k8s-'"
else
  bad "ELBv2 load balancers with prefix 'k8s-' still exist"
  aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?starts_with(LoadBalancerName,'k8s-')].[LoadBalancerName,Type,State.Code,DNSName]" \
    --output table || true
  FAIL=1
fi

# Target groups by name prefix (k8s-)
tg_prefix_out="$(aws_query_or_fail "Describe target groups" aws elbv2 describe-target-groups --region "$REGION" \
  --query "TargetGroups[?starts_with(TargetGroupName,'k8s-')].[TargetGroupName]" --output text || true)"

if [[ -z "${tg_prefix_out// }" ]]; then
  ok "No Target Groups with prefix 'k8s-'"
else
  bad "Target Groups with prefix 'k8s-' still exist"
  aws elbv2 describe-target-groups --region "$REGION" \
    --query "TargetGroups[?starts_with(TargetGroupName,'k8s-')].[TargetGroupName,TargetGroupArn]" \
    --output table || true
  FAIL=1
fi

# VPC-dependent checks (stronger + catches non-k8s names)
if [[ -n "$VPC_ID" ]]; then
  # Any ELBv2 LBs in this VPC
  lb_vpc_out="$(aws_query_or_fail "Describe ELBv2 load balancers (VPC scope)" aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?VpcId=='${VPC_ID}'].[LoadBalancerName,Type,State.Code,DNSName]" --output text || true)"

  if [[ -z "${lb_vpc_out// }" ]]; then
    ok "No ELBv2 load balancers in VPC ${VPC_ID}"
  else
    bad "ELBv2 load balancers still exist in VPC ${VPC_ID}"
    aws elbv2 describe-load-balancers --region "$REGION" \
      --query "LoadBalancers[?VpcId=='${VPC_ID}'].[LoadBalancerName,Type,State.Code,DNSName,LoadBalancerArn]" \
      --output table || true
    FAIL=1
  fi

  # Any Target Groups in this VPC
  tg_vpc_out="$(aws_query_or_fail "Describe target groups (VPC scope)" aws elbv2 describe-target-groups --region "$REGION" \
    --query "TargetGroups[?VpcId=='${VPC_ID}'].[TargetGroupName]" --output text || true)"

  if [[ -z "${tg_vpc_out// }" ]]; then
    ok "No Target Groups in VPC ${VPC_ID}"
  else
    bad "Target Groups still exist in VPC ${VPC_ID}"
    aws elbv2 describe-target-groups --region "$REGION" \
      --query "TargetGroups[?VpcId=='${VPC_ID}'].[TargetGroupName,TargetGroupArn]" \
      --output table || true
    FAIL=1
  fi

  # Security Groups (non-default)
  sg_out="$(aws_query_or_fail "Describe security groups" aws ec2 describe-security-groups --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" \
    --query "SecurityGroups[?GroupName!='default'].[GroupId,GroupName]" --output text || true)"

  if [[ -z "${sg_out// }" ]]; then
    ok "No non-default Security Groups in VPC ${VPC_ID}"
  else
    bad "Non-default Security Groups still exist in VPC ${VPC_ID}"
    aws ec2 describe-security-groups --region "$REGION" \
      --filters Name=vpc-id,Values="$VPC_ID" \
      --query "SecurityGroups[?GroupName!='default'].{Id:GroupId,Name:GroupName}" \
      --output table || true
    FAIL=1
  fi

  # VPC Endpoints
  vpce_out="$(aws_query_or_fail "Describe VPC endpoints" aws ec2 describe-vpc-endpoints --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" \
    --query "VpcEndpoints[].VpcEndpointId" --output text || true)"

  if [[ -z "${vpce_out// }" ]]; then
    ok "No VPC Endpoints in VPC ${VPC_ID}"
  else
    bad "VPC Endpoints still exist in VPC ${VPC_ID}"
    aws ec2 describe-vpc-endpoints --region "$REGION" \
      --filters Name=vpc-id,Values="$VPC_ID" \
      --query "VpcEndpoints[].{Id:VpcEndpointId,Service:ServiceName,State:State,Type:VpcEndpointType}" \
      --output table || true
    FAIL=1
  fi

  # ENIs (most common VPC-delete blocker)
  eni_count="$(aws_query_or_fail "Describe network interfaces" aws ec2 describe-network-interfaces --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" \
    --query "length(NetworkInterfaces[])" --output text || echo "0")"

  if [[ "${eni_count}" -eq 0 ]]; then
    ok "No ENIs in VPC ${VPC_ID}"
  else
    bad "ENIs still exist in VPC ${VPC_ID}: ${eni_count}"
    aws ec2 describe-network-interfaces --region "$REGION" \
      --filters Name=vpc-id,Values="$VPC_ID" \
      --query "NetworkInterfaces[].{Id:NetworkInterfaceId,Status:Status,Desc:Description,Type:InterfaceType,Sub:SubnetId,Attach:Attachment.AttachmentId,Owner:OwnerId}" \
      --output table || true
    FAIL=1
  fi

else
  warn "VPC_ID is unset; skipping VPC-scoped AWS checks (LBs/SGs/VPCE/ENIs)."
fi

echo
echo "=============================="
if [[ "$FAIL" -eq 0 ]]; then
  echo -e "${GREEN}ALL CHECKS PASSED${NC} ✅"
  echo "Safe to run terraform destroy."
  exit 0
else
  echo -e "${RED}CHECKS FAILED${NC} ❌"
  echo "Fix the NOT OK items above before terraform destroy."
  exit 2
fi
