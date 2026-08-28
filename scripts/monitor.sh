#!/usr/bin/env bash
# Snapshots cluster, node, add-on and pod state at a fixed interval.
# Runs until killed. Started in the background by the Makefile while an upgrade
# or a rollback is in progress, so the log shows what happened to the workload.
#
# Usage:
#   CLUSTER=my-eks ./scripts/monitor.sh              # 15s interval
#   CLUSTER=my-eks INTERVAL=30 ./scripts/monitor.sh

set -uo pipefail

CLUSTER="${CLUSTER:?CLUSTER is required}"
INTERVAL="${INTERVAL:-15}"
APP_LABEL="${APP_LABEL:-app=demo-app}"

export AWS_PAGER=""

ts() { date '+%Y-%m-%d %H:%M:%S%z'; }

snapshot() {
  # During the first minutes of a fresh deploy the cluster does not exist yet.
  # One line keeps the log readable until it does.
  local status
  status="$(aws eks describe-cluster --name "${CLUSTER}" \
    --query 'cluster.status' --output text 2>/dev/null)"
  if [ -z "${status}" ] || [ "${status}" = "None" ]; then
    printf '[%s] cluster %s not available yet\n' "$(ts)" "${CLUSTER}"
    return
  fi

  printf '\n============================================================\n'
  printf '[%s] SNAPSHOT\n' "$(ts)"
  printf '============================================================\n'

  printf '\n-- control plane --\n'
  aws eks describe-cluster --name "${CLUSTER}" \
    --query 'cluster.{version:version,status:status,platform:platformVersion}' \
    --output table 2>&1 || printf '(describe-cluster failed)\n'

  printf '\n-- node groups --\n'
  for ng in $(aws eks list-nodegroups --cluster-name "${CLUSTER}" \
    --query 'nodegroups[]' --output text 2>/dev/null); do
    aws eks describe-nodegroup --cluster-name "${CLUSTER}" --nodegroup-name "${ng}" \
      --query 'nodegroup.{name:nodegroupName,version:version,release:releaseVersion,status:status}' \
      --output table 2>&1 || true
  done

  printf '\n-- add-ons --\n'
  for addon in $(aws eks list-addons --cluster-name "${CLUSTER}" \
    --query 'addons[]' --output text 2>/dev/null); do
    aws eks describe-addon --cluster-name "${CLUSTER}" --addon-name "${addon}" \
      --query 'addon.{name:addonName,version:addonVersion,status:status}' \
      --output text 2>&1 || true
  done

  printf '\n-- insights that are not PASSING --\n'
  aws eks list-insights --cluster-name "${CLUSTER}" \
    --query 'insights[?insightStatus.status!=`PASSING`].{name:name,status:insightStatus.status,category:category}' \
    --output table 2>&1 | head -30 || printf '(list-insights failed)\n'

  # Node rollback progress. The count per kubelet version shows how far the
  # node group has moved while the update is running.
  printf '\n-- kubelet versions --\n'
  kubectl get nodes --no-headers \
    -o custom-columns='V:.status.nodeInfo.kubeletVersion' 2>/dev/null \
    | sort | uniq -c || printf '(kubectl get nodes failed)\n'

  printf '\n-- nodes --\n'
  kubectl get nodes -o wide 2>&1 || true

  # Deprecated API usage has to be resolved before rolling back, because objects
  # created with a newer API are not removed by the rollback.
  printf '\n-- deprecated API usage --\n'
  kubectl get --raw /metrics 2>/dev/null \
    | grep '^apiserver_requested_deprecated_apis' || printf '(none)\n'

  printf '\n-- demo app pods --\n'
  kubectl get pods -l "${APP_LABEL}" -o wide 2>&1 || true

  printf '\n-- pods that are not Running or Completed --\n'
  not_ready="$(kubectl get pods -A --no-headers 2>/dev/null \
    | awk '$4 != "Running" && $4 != "Completed" {print}')"
  if [ -z "${not_ready}" ]; then
    printf '(all pods Running or Completed)\n'
  else
    printf '%s\n' "${not_ready}"
  fi

  printf '\n-- recent warning events --\n'
  kubectl get events -A --sort-by=.lastTimestamp \
    --field-selector type!=Normal 2>/dev/null | tail -15 || printf '(none)\n'
}

printf '[%s] monitor start (cluster=%s interval=%ss)\n' "$(ts)" "${CLUSTER}" "${INTERVAL}"
trap 'printf "\n[%s] monitor stop\n" "$(ts)"; exit 0' INT TERM

while :; do
  snapshot
  sleep "${INTERVAL}"
done
