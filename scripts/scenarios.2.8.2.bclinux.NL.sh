#!/bin/bash

## 4 部署 SmartDNS 服务

###bash
export CTR_REGISTRY=172.168.226.1:5000/flomesh
export PIPY_REGISTRY=172.168.226.1:5000/flomesh
export CTR_XNET_REGISTRY=172.168.226.1:5000/flomesh
export CTR_TAG=latest
export CTR_XNET_TAG=bclinux-euler-22.10-latest

fsm_cluster_name=C1 sidecar=NodeLevel k8s=true mesh=true e4lb=true e4lb_cni=calicoVxlan make deploy-smartdns

# 无须 injector, 删除 injector
kubectl delete deployments.apps -n fsm-system fsm-injector
###

## 5 部署 SmartDNS FGW 服务

### 5.1 部署 FGW

###bash
kubectl patch meshconfig fsm-mesh-config -n fsm-system -p '{"spec":{"sidecar":{"xnetDNSProxy":{"enable":true,"upstreams":[{"name":"fsm-gateway-fsm-system-smart-dns-fgw-udp","namespace":"fsm-system","port":10053}]}}}}'  --type=merge

# 指定 fgw 运行所在的 node
kubectl apply -n fsm-system -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: smart-dns-fgw-config
data:
  values.yaml: |
    fsm:
      gateway:
        nodeSelector:
          kubernetes.io/hostname: worker1.bc
EOF

kubectl apply -n fsm-system -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: smart-dns-fgw
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
  infrastructure:
    parametersRef:
      group: ""
      kind: ConfigMap
      name: smart-dns-fgw-config
EOF
###

### 5.2 配置 INGRESS 方向 DNS filter

###bash
kubectl -n fsm-system apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: UDPRoute
metadata:
  name: ingress-dns-route
spec:
  parentRefs:
    - name: smart-dns-fgw
      namespace: fsm-system
      port: 53
  rules:
  - name: ingress-dns
    backendRefs:
    - name: kube-dns
      namespace: kube-system
      port: 53
---
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: DNSModifier
metadata:
  name: ingress-dns-resolve-db
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
      rule: ingress-dns
  filterRefs:
    - group: extension.gateway.flomesh.io
      kind: Filter
      name: ingress-dns-filter
EOF
###

### 5.3 配置 EGRESS 方向 DNS filter

###bash
kubectl -n fsm-system apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: UDPRoute
metadata:
  name: egress-dns-route
spec:
  parentRefs:
    - name: smart-dns-fgw
      namespace: fsm-system
      port: 10053
  rules:
  - name: egress-dns
    backendRefs:
    - name: kube-dns
      namespace: kube-system
      port: 53
---
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: DNSModifier
metadata:
  name: egress-dns-resolve-db
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
      rule: egress-dns
  filterRefs:
    - group: extension.gateway.flomesh.io
      kind: Filter
      name: egress-dns-filter
EOF
###

### 5.4 SmartDNS UDPRoute 授权

###bash
kubectl -n kube-system apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: grant-smart-dns-route
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: UDPRoute
      namespace: fsm-system
  to:
    - group: ""
      kind: Service
      name: kube-dns
EOF
###

## 6 创建租户

### 6.1 创建租户空间

###bash
kubectl create namespace tenant-liaoning
###

### 6.2 部署模拟业务

###bash
kubectl apply -n tenant-liaoning -f ./manifests/native/curl.yaml
###

## 7 导入租户 Eureka 服务

### 7.1 部署 eureka connector

###
kubectl apply -n tenant-liaoning -f - <<EOF
kind: EurekaConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: eureka-to-tenant-liaoning
spec:
  httpAddr: http://192.168.127.53:8761/eureka
  deriveNamespace: tenant-liaoning
  syncFromK8S:
    enable: false
  syncToK8S:
    enable: true
    conversionStrategy:
      enable: true #启用服务名转换策略
EOF
###

### 7.3 导入 eureka 上的服务

###bash
kubectl get eurekaconnector -n tenant-liaoning eureka-to-tenant-liaoning -o json | jq '.spec.syncToK8S.conversionStrategy.serviceConversions += [{"service": "httpbin", "convertName": "httpbin-eureka"}]' | kubectl apply -f -
###

## 8 导入租户 Nacos 服务

### 8.1 部署 nacos connector

###
kubectl apply -n tenant-liaoning -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: nacos-to-tenant-liaoning
spec:
  httpAddr: 192.168.127.54:8848
  deriveNamespace: tenant-liaoning
  syncFromK8S:
    enable: false
  syncToK8S:
    enable: true
    conversionStrategy:
      enable: true #启用服务名转换策略
EOF
###

### 8.3 导入 nacos 上的服务

###bash
kubectl get nacosconnector -n tenant-liaoning nacos-to-tenant-liaoning -o json | jq '.spec.syncToK8S.conversionStrategy.serviceConversions += [{"service": "httpbin", "convertName": "httpbin-nacos"}]' | kubectl apply -f -
###

## 9 SmartDNS 业务测试

### 9.1 EIP 业务测试

#### 9.1.1 配置 EIP

##### 9.1.1.1 tenant-liaoning/httpbin 配置 EIP

###bash
replicas=2 envsubst < ./manifests/native/httpbin-hostname.yaml | kubectl apply -n tenant-liaoning -f -

kubectl apply -n tenant-liaoning -f - <<EOF
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

##### 9.1.1.2 tenant-liaoning/httpbin-eureka 配置 EIP

###bash
kubectl apply -n tenant-liaoning -f - <<EOF
kind: EIPAdvertisement
apiVersion: xnetwork.flomesh.io/v1alpha1
metadata:
  name: httpbin-eureka
spec:
  service:
    name: httpbin-eureka
  eip: 192.168.127.187
  nodes:
  - worker2.bc
EOF
###

##### 9.1.1.3 tenant-liaoning/httpbin-nacos 配置 EIP

###bash
kubectl apply -n tenant-liaoning -f - <<EOF
kind: EIPAdvertisement
apiVersion: xnetwork.flomesh.io/v1alpha1
metadata:
  name: httpbin-nacos
spec:
  service:
    name: httpbin-nacos
  eip: 192.168.127.188
  nodes:
  - worker2.bc
EOF
###

### 9.2 DNS 业务测试

#### 9.2.1 配置 DNS Resolve DB

##### 9.2.1.1 配置全局 DNS Resolve DB

###bash
kubectl get dnsmodifier -n fsm-system egress-dns-resolve-db -o json | jq '.spec.zones["global"].domains += [{"answer": {"rdata": "6.6.6.6"},"name": "google.com"}]' | kubectl apply -f -
###
