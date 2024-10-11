#!/bin/bash

export clusters="C1"
make k3d-up

fsm_cluster_name=C1 make deploy-fsm

kubectl create namespace ebpf
fsm namespace add ebpf
kubectl apply -n ebpf -f manifests/curl.yaml

sleep 3

kubectl wait --all --for=condition=ready pod -n ebpf -l app=curl --timeout=180s