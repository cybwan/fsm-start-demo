#!/bin/bash

## 4 部署 SmartDNS 服务

###bash
export CTR_REGISTRY=172.168.226.1:5000/flomesh
export PIPY_REGISTRY=172.168.226.1:5000/flomesh
export CTR_XNET_REGISTRY=172.168.226.1:5000/flomesh
export CTR_TAG=latest
export CTR_XNET_TAG=bclinux-euler-22.10-latest

fsm_cluster_name=C1 sidecar=NodeLevel k8s=true mesh=true e4lb=true e4lb_cni=calicoVxlan make deploy-smartdns

kubectl scale deployment -n fsm-system fsm-injector --replicas=0
###

## 5 部署 FGW DNS Proxy

### 5.1 部署 FGW

###bash
kubectl patch meshconfig fsm-mesh-config -n fsm-system -p '{"spec":{"sidecar":{"xnetDNSProxy":{"enable":true,"upstreams":[{"name":"fsm-gateway-fsm-system-fgw-dns-proxy-udp","namespace":"fsm-system","port":10053}]}}}}'  --type=merge

kubectl apply -n fsm-system -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: fgw-dns-proxy
spec:
  gatewayClassName: fsm
  listeners:
    - protocol: UDP
      port: 10053
      name: egress-dns
      allowedRoutes:
        namespaces:
          from: All
    - protocol: UDP
      port: 53
      name: ingress-dns
      allowedRoutes:
        namespaces:
          from: All
EOF

sleep 15s

kubectl patch daemonset fsm-gateway-fsm-system-fgw-dns-proxy -n fsm-system -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"worker1.bc"}}}}}'  --type=merge
###

### 5.2 配置 INGRESS 方向 DNS filter

###bash
kubectl -n kube-system apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: UDPRoute
metadata:
  name: ingress-dns-route
spec:
  parentRefs:
    - name: fgw-dns-proxy
      namespace: fsm-system
      port: 10053
  rules:
  - name: dns
    backendRefs:
    - name: kube-dns
      port: 53
---
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: DNSModifier
metadata:
  name: ingress-dns-resolve-db
spec:
  domains:
    - name: google.com
      answer:
        rdata: 11.11.11.11
    - name: httpbin.demo.global
      answer:
        rdata: 192.168.127.186
---
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: Filter
metadata:
  name: ingress-dns-filter
spec:
  type: DNSModifier
  configRef:
    group: extension.gateway.flomesh.io
    kind: DNSModifier
    name: ingress-dns-resolve-db
---
apiVersion: gateway.flomesh.io/v1alpha2
kind: RouteRuleFilterPolicy
metadata:
  name: ingress-dns-filter-policy
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: UDPRoute
      name: ingress-dns-route
      rule: dns
  filterRefs:
    - group: extension.gateway.flomesh.io
      kind: Filter
      name: ingress-dns-filter
EOF
###

### 5.3 配置 EGRESS 方向 DNS filter

###bash
kubectl -n kube-system apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: UDPRoute
metadata:
  name: egress-dns-route
spec:
  parentRefs:
    - name: fgw-dns-proxy
      namespace: fsm-system
      port: 53
  rules:
  - name: dns
    backendRefs:
    - name: kube-dns
      port: 53
---
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: DNSModifier
metadata:
  name: egress-dns-resolve-db
spec:
  domains:
    - name: google.com
      answer:
        rdata: 22.22.22.22
---
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: Filter
metadata:
  name: egress-dns-filter
spec:
  type: DNSModifier
  configRef:
    group: extension.gateway.flomesh.io
    kind: DNSModifier
    name: egress-dns-resolve-db
---
apiVersion: gateway.flomesh.io/v1alpha2
kind: RouteRuleFilterPolicy
metadata:
  name: egress-dns-filter-policy
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: UDPRoute
      name: egress-dns-route
      rule: dns
  filterRefs:
    - group: extension.gateway.flomesh.io
      kind: Filter
      name: egress-dns-filter
EOF
###

## 6 导入 Eureka 服务

### 6.1 创建 derive-eureka namespace

###bash
kubectl create namespace eureka
fsm namespace add eureka
kubectl patch namespace eureka -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"eureka"}}}'  --type=merge
###

### 6.2 部署 eureka connector

###
kubectl apply -n eureka -f - <<EOF
kind: EurekaConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: to-c1-eureka
spec:
  httpAddr: http://192.168.127.53:8761/eureka
  deriveNamespace: eureka
  asInternalServices: false
  syncToK8S:
    enable: true
  syncFromK8S:
    enable: false
EOF
###

## 7 导入 Nacos 服务

### 7.1 创建 derive-nacos namespace

###bash
kubectl create namespace nacos
fsm namespace add nacos
kubectl patch namespace nacos -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"nacos"}}}'  --type=merge
###

### 7.2 部署 nacos connector

###
kubectl apply -n nacos -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: to-c1-nacos
spec:
  httpAddr: 192.168.127.54:8848
  deriveNamespace: nacos
  asInternalServices: false
  syncToK8S:
    enable: true
  syncFromK8S:
    enable: false
EOF
###

## 8 E4LB 业务测试

### 8.1 demo/httpbin 配置 EIP

###bash
WITH_MESH=false replicas=2 make deploy-hostname-httpbin

kubectl apply -n demo -f - <<EOF
kind: EIPAdvertisement
apiVersion: xnetwork.flomesh.io/v1alpha1
metadata:
  name: httpbin
spec:
  service:
    name: httpbin
  eip: 192.168.127.186
  nodes:
  - worker2.bc
EOF
###

### 8.2 eureka/httpbin 配置 EIP

###bash
kubectl apply -n eureka -f - <<EOF
kind: EIPAdvertisement
apiVersion: xnetwork.flomesh.io/v1alpha1
metadata:
  name: httpbin
spec:
  service:
    name: httpbin
  eip: 192.168.127.187
  nodes:
  - worker2.bc
EOF
###

### 8.3 nacos/httpbin 配置 EIP

###bash
kubectl apply -n nacos -f - <<EOF
kind: EIPAdvertisement
apiVersion: xnetwork.flomesh.io/v1alpha1
metadata:
  name: httpbin
spec:
  service:
    name: httpbin
  eip: 192.168.127.188
  nodes:
  - worker2.bc
EOF
###

### 8.4 业务功能测试

#### 8.4.1 K8S集群内测试

##### 8.4.1.1 部署模拟业务

###bash
kubectl create namespace curl
kubectl apply -n curl -f ./manifests/native/curl.yaml
###