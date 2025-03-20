#!/bin/bash

# 场景 Consul 单集群微服务融合测试

## 1 部署 C1 集群

###bash
clusters="C1" make k3d-up
###

## 2 部署服务

### 2.1 C1集群

###bash
kubecm switch k3d-C1
###

### 2.2 部署 FSM Mesh

###bash
fsm_cluster_name=C1 sidecar=NodeLevel make deploy-fsm
###

### 2.3 部署 fgw

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
      port: 10080
      name: igrs-http
      allowedRoutes:
        namespaces:
          from: All
    - protocol: HTTP
      port: 15001
      name: mesh-http
      allowedRoutes:
        namespaces:
          from: All
EOF

kubectl apply -n fsm-system -f - <<EOF
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

### 2.4 部署 consul 服务

###bash
make consul-deploy
#PORT_FORWARD="18501:8500" make consul-port-forward &

export c1_consul_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=consul -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_consul_cluster_ip $c1_consul_cluster_ip

export c1_consul_external_ip="$(kubectl get svc -n default --field-selector metadata.name=consul -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_consul_external_ip $c1_consul_external_ip

export c1_consul_pod_ip="$(kubectl get pod -n default --selector app=consul -o jsonpath='{.items[0].status.podIP}')"
echo c1_consul_pod_ip $c1_consul_pod_ip
###

### 2.5 配置 consul 服务访问控制策略

###bash
kubectl create namespace fsm-policy
fsm namespace add fsm-policy

kubectl apply -n fsm-policy -f - <<EOF
kind: AccessControl
apiVersion: xnetwork.flomesh.io/v1alpha1
metadata:
  name: global
spec:
  services:
  - namespace: default
    name: consul
    withEndpointIPs: true
EOF
###

### 2.6 创建 derive-consul namespace

###bash
kubectl create namespace derive-consul
fsm namespace add derive-consul
kubectl patch namespace derive-consul -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"consul"}}}'  --type=merge
###

### 2.7 部署 consul connector(c1-consul-to-c1-derive-consul)

###
kubectl apply -n fsm-system -f - <<EOF
kind: ConsulConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-consul-to-c1-derive-consul
spec:
  httpAddr: $c1_consul_cluster_ip:8500
  deriveNamespace: derive-consul
  asInternalServices: true
  syncToK8S:
    enable: true
  syncFromK8S:
    enable: false
EOF
###

### 2.8 部署 fgw connector

###bash
kubectl apply -n fsm-system -f - <<EOF
kind: GatewayConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: node-sidecar
spec:
  gatewayName: node-sidecar
  ingress:
    ipSelector: ExternalIP
    httpPort: 10080
  egress:
    ipSelector: ClusterIP
    httpPort: 15001
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - derive-consul
EOF
###

### 2.9 部署 consul 微服务

###bash
WITH_MESH=true fsm_cluster_name=c1 replicas=2 make deploy-consul-httpbin
WITH_MESH=true fsm_cluster_name=c1 replicas=1 make deploy-consul-curl
###