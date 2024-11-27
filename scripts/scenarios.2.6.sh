#!/bin/bash

# 场景 Nacos 单集群微服务融合测试

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

## 3 Nacos 单集群微服务测试

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

### 3.2 部署 Nacos 服务

###bash
make nacos-auth-deploy

#make nacos-deploy
#kubectl patch deployments -n default nacos --type=json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name":"NACOS_AUTH_ENABLE","value":"true"}},{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name":"NACOS_AUTH_TOKEN","value":"SecretKeyM1Z2WDc4dnVyZkQ3NmZMZjZ3RHRwZnJjNFROdkJOemEK"}},{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name":"NACOS_AUTH_IDENTITY_KEY","value":"nacos"}},{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name":"NACOS_AUTH_IDENTITY_VALUE","value":"nacos"}}]'
#kubectl wait --all --for=condition=ready pod -n default -l app=nacos --timeout=180s

#PORT_FORWARD="8848:8848" make nacos-port-forward &

export c1_nacos_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=nacos -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_nacos_cluster_ip $c1_nacos_cluster_ip

export c1_nacos_external_ip="$(kubectl get svc -n default --field-selector metadata.name=nacos -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_nacos_external_ip $c1_nacos_external_ip

export c1_nacos_pod_ip="$(kubectl get pod -n default --selector app=nacos -o jsonpath='{.items[0].status.podIP}')"
echo c1_nacos_pod_ip $c1_nacos_pod_ip
###

### 3.3 配置Nacos 服务访问控制策略

###bash
kubectl create namespace fsm-policy
fsm namespace add fsm-policy

kubectl apply -f - <<EOF
kind: AccessControl
apiVersion: xnetwork.flomesh.io/v1alpha1
metadata:
  name: global
  namespace: fsm-policy
spec:
  services:
  - namespace: default
    name: nacos
EOF
###

### 3.4 创建 derive-nacos namespace

###bash
kubectl create namespace derive-nacos
fsm namespace add derive-nacos
kubectl patch namespace derive-nacos -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"nacos"}}}'  --type=merge
###

### 3.5 部署 nacos connector(c1-nacos-to-c1-derive-nacos)

###
kubectl apply  -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-nacos-to-c1-derive-nacos
spec:
  auth:
    username: nacos
    password: nacos
  httpAddr: $c1_nacos_cluster_ip:8848
  deriveNamespace: derive-nacos
  asInternalServices: true
  syncToK8S:
    enable: true
  syncFromK8S:
    enable: false
EOF
###

### 3.6 部署 fgw connector

###bash
kubectl apply  -f - <<EOF
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
      - derive-nacos
EOF
###

### 3.7 部署 Nacos 微服务

###bash
WITH_MESH=true make deploy-nacos-httpbin
WITH_MESH=true make deploy-nacos-curl
###