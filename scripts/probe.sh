#!/usr/bin/env bash
# Records how many Service endpoints are Ready, once per second.
# The count never dropping to 0 is the evidence that the Service stayed available
# while individual pods were replaced.
#
# Usage:
#   ./scripts/probe.sh                     # 1s interval, svc demo-app
#   SVC=demo-app INTERVAL=1 ./scripts/probe.sh

set -uo pipefail

SVC="${SVC:-demo-app}"
NS="${NS:-default}"
INTERVAL="${INTERVAL:-1}"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

printf '[%s] probe start (service=%s interval=%ss)\n' "$(ts)" "${SVC}" "${INTERVAL}"
trap 'printf "[%s] probe stop\n" "$(ts)"; exit 0' INT TERM

prev=""
zero_since=""

while :; do
  # Ready addresses on the EndpointSlice are what kube-proxy actually forwards to.
  ready="$(kubectl get endpointslice -n "${NS}" -l "kubernetes.io/service-name=${SVC}" \
    -o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{"\n"}{end}' 2>/dev/null \
    | grep -c '^true$')"
  ready="${ready:-0}"

  now="$(ts)"
  if [ "${ready}" != "${prev}" ]; then
    printf '[%s] ready endpoints: %s\n' "${now}" "${ready}"
    if [ "${ready}" = "0" ]; then
      zero_since="$(date +%s)"
      printf '[%s] SERVICE HAS NO READY ENDPOINT\n' "${now}"
    elif [ -n "${zero_since}" ]; then
      printf '[%s] recovered after %s seconds with no ready endpoint\n' \
        "${now}" "$(( $(date +%s) - zero_since ))"
      zero_since=""
    fi
    prev="${ready}"
  fi

  sleep "${INTERVAL}"
done
