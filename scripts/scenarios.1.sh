#!/bin/bash

export clusters="C1"
make k3d-up

fsm_cluster_name=C1 make deploy-fsm

kubectl create namespace ebpf
fsm namespace add ebpf
kubectl apply -n ebpf -f manifests/curl.yaml

sleep 3

kubectl wait --all --for=condition=ready pod -n ebpf -l app=curl --timeout=180s

export interceptor_pod=$(kubectl get pods --selector app=fsm-interceptor -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $1}')

kubectl exec -n fsm-system $interceptor_pod -- mount -t debugfs debugfs /sys/kernel/debug

kubectl exec -n fsm-system $interceptor_pod -- tailf /sys/kernel/debug/tracing/trace_pipe