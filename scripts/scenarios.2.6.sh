#!/bin/bash

# 场景 慢启动预热策略测试

## 1 部署 K8S 集群

###bash
clusters="C1" make k3d-up
###

## 2 部署服务

###bash
kubecm switch k3d-C1
###

### 2.1 部署 FSM Mesh

###bash
fsm_cluster_name=C1 sidecar=PodLevel make deploy-fsm
###

### 2.2 部署微服务

###bash
kubectl delete namespace demo --ignore-not-found
kubectl create namespace demo
fsm namespace add demo
kubectl apply -n demo -f ./manifests/native/httpbin.yaml
sleep 2
kubectl wait --all --for=condition=ready pod -n demo -l app=httpbin --timeout=180s
###

### 2.3 启用慢启动预热策略

###bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableTrafficWarmupPolicy":true}}}'  --type=merge
###

### 2.4 设置慢启动预热策略

#### 2.4.1 服务级别慢启动预热策略

###bash
kubectl apply -n demo -f - <<EOF
kind: TrafficWarmup
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: httpbin
spec:
  minWeight: 15
  maxWeight: 100
  duration: 100s
EOF
###
