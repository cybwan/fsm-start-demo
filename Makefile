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

.PHONY: mount-debugfs
mount-debugfs:
	export INTERCEPTOR_POD=$$(kubectl get pods --selector app=fsm-interceptor -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl exec -n fsm-system "$$INTERCEPTOR_POD" -- mount -t debugfs debugfs /sys/kernel/debug

.PHONY: tail-interceptor
tail-interceptor:
	export INTERCEPTOR_POD=$$(kubectl get pods --selector app=fsm-interceptor -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl logs "$$INTERCEPTOR_POD" -n fsm-system -c fsm-interceptor -f

.PHONY: tail-interceptor-kernel
tail-interceptor-kernel:
	export INTERCEPTOR_POD=$$(kubectl get pods --selector app=fsm-interceptor -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl exec "$$INTERCEPTOR_POD" -n fsm-system -- cat /sys/kernel/debug/tracing/trace_pipe | grep bpf_trace_printk

.PHONY: kill-interceptor-kernel-reset
tail-interceptor-kernel-reset:
	export INTERCEPTOR_POD=$$(kubectl get pods --selector app=fsm-interceptor -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	export CAT_PID=$$(kubectl exec "$$INTERCEPTOR_POD" -n fsm-system -- ps aux | grep cat | grep -v grep | awk '{print $$2}');\
	kubectl exec "$$INTERCEPTOR_POD" -n fsm-system -- kill -9 $$CAT_PID

.PHONY: shell-interceptor
shell-interceptor:
	export INTERCEPTOR_POD=$$(kubectl get pods --selector app=fsm-interceptor -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl exec -it "$$INTERCEPTOR_POD" -n fsm-system -- bash

.PHONY: up-scenarios-1
up-scenarios-1:
	./scripts/scenarios.1.sh

.PHONY: down-scenarios-1
down-scenarios-1:
	export clusters="C1";make k3d-reset