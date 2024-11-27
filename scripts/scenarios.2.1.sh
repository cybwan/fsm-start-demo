#!/bin/bash

# 场景 HTTP 业务测试

## 1 部署 K8S 集群

###bash
export clusters="C1"
make k3d-up
kubecm switch k3d-C1
###

## 2 部署网格服务

###bash
fsm_cluster_name=C1 make deploy-fsm
###

## 3 HTTP 业务测试

### 3.1 部署 fgw

###bash
kubectl apply -n fsm-system -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: node-sidecar
spec:
  gatewayClassName: fsm
  listeners:
    - protocol: HTTP
      port: 15001
      name: mesh
      allowedRoutes:
        namespaces:
          from: All
EOF

kubectl apply -f - <<EOF
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: ListenerFilter
metadata:
  name: node-sidecar-accesslog
  namespace: fsm-system
spec:
  type: AccessLog
  aspect: Route
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: node-sidecar
      port: 15001
EOF
###

### 3.2 部署HTTP模拟服务

###bash
#模拟业务服务
kubectl create namespace mesh-in
fsm namespace add mesh-in
kubectl apply -n mesh-in -f manifests/curl.yaml
kubectl apply -n mesh-in -f manifests/httpbin.yaml
sleep 2
kubectl wait --all --for=condition=ready pod -n mesh-in -l app=curl --timeout=180s
kubectl wait --all --for=condition=ready pod -n mesh-in -l app=httpbin --timeout=180s

kubectl create namespace mesh-out
kubectl apply -n mesh-out -f manifests/curl.yaml
sleep 2
kubectl wait --all --for=condition=ready pod -n mesh-out -l app=curl --timeout=180s
###

### 3.3 部署 fgw connector

###bash
kubectl apply  -f - <<EOF
kind: GatewayConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: node-sidecar
spec:
  gatewayName: node-sidecar
  ingress:
    ipSelector: ClusterIP
    httpPort: 15001
  egress:
    ipSelector: ClusterIP
    httpPort: 15001
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - mesh-in
EOF
###