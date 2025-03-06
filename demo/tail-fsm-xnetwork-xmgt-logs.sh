#!/bin/bash

set -aueo pipefail

node="${node:-k3d-c1-server-0}"

# shellcheck disable=SC1091
POD="$(kubectl get pods -n fsm-system --selector app=fsm-xnetwork --field-selector spec.nodeName=${node} --no-headers | awk '{print $1}' | head -n1)"
kubectl logs "${POD}" -n fsm-system -c fsm-xmgt -f
