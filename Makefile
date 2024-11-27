#!make

WITH_MESH ?= false
WITH_PROXY ?=
COUNT ?= 1000

K3D_HOST_IP ?= 192.168.127.91

fsm_cluster_name ?= fsm
replicas ?= 1

.PHONY: k3d-up
k3d-up:
	./scripts/k3d-with-registry-multicluster$(WITH_PROXY).sh
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
