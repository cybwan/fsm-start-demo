#!make

PORT_FORWARD ?= 14001:14001
WITH_MESH ?= false
COUNT ?= 1000

fsm_cluster_name ?= fsm
replicas ?= 1

.PHONY: k3d-up
k3d-up:
	./scripts/k3d-with-registry-multicluster.sh
	kubecm list

.PHONY: k3d-proxy-up
k3d-proxy-up:
	./scripts/k3d-with-registry-multicluster-with-proxy.sh
	kubecm list

.PHONY: k3d-reset
k3d-reset:
	./scripts/k3d-multicluster-cleanup.sh

.PHONY: deploy-fsm
deploy-fsm:
	$fsm_cluster_name=$(fsm_cluster_name) scripts/deploy-fsm.sh

.PHONY: tail-interceptor
tail-interceptor:
	export POD=$$(kubectl get pods --selector app=fsm-interceptor -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl logs "$$POD" -n fsm-system -c fsm-interceptor -f

.PHONY: up-scenarios-1
up-scenarios-1:
	./scripts/scenarios.1.sh

.PHONY: down-scenarios-1
down-scenarios-1:
	export clusters="C1 C2 C3";make k3d-reset