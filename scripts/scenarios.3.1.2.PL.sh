#!/bin/bash

# 场景 Eureka 单集群微服务融合测试

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
fsm_cluster_name=C1 sidecar=PodLevel make deploy-fsm
###

### 2.3 启用按请求负载均衡策略

###bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"http1PerRequestLoadBalancing":true}}}' --type=merge
###

### 2.4 部署 Eureka 微服务

###bash
make eureka-deploy
#PORT_FORWARD="18761:8761" make eureka-port-forward &

export c1_eureka_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=eureka -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_eureka_cluster_ip $c1_eureka_cluster_ip

export c1_eureka_external_ip="$(kubectl get svc -n default --field-selector metadata.name=eureka -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_eureka_external_ip $c1_eureka_external_ip

export c1_eureka_pod_ip="$(kubectl get pod -n default --selector app=eureka -o jsonpath='{.items[0].status.podIP}')"
echo c1_eureka_pod_ip $c1_eureka_pod_ip

kubectl create namespace fsm-policy
fsm namespace add fsm-policy

kubectl apply -f - <<EOF
kind: AccessControl
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: global
  namespace: fsm-policy
spec:
  sources:
  - kind: Service
    namespace: default
    name: eureka
EOF

WITH_MESH=true fsm_cluster_name=c1 replicas=2 make deploy-eureka-httpbin
WITH_MESH=true fsm_cluster_name=c1 replicas=1 make deploy-eureka-curl
###

## 3 微服务融合

### 3.1 C1 集群

###bash
kubecm switch k3d-C1
###

### 3.2 导入本集群 eureka 微服务

#### 3.2.1 创建 derive-local namespace

###bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"eureka"}}}'  --type=merge
###

#### 3.2.2 部署 eureka connector(c1-eureka-to-c1-derive-local)

###
kubectl apply  -f - <<EOF
kind: EurekaConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-eureka-to-c1-derive-local
spec:
  httpAddr: http://$c1_eureka_cluster_ip:8761/eureka
  deriveNamespace: derive-local
  asInternalServices: true
  syncToK8S:
    enable: true
    filterIpRanges:
      - 10.101.0.0/16
    withGateway:
      enable: false
  syncFromK8S:
    enable: false
EOF
###