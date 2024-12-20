#!/bin/bash

# 场景 Nebula-GRPC 单集群微服务融合测试

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

### 2.2 部署 zookeeper 服务

###bash
make zk-deploy
make zk-port-forward

export c1_zookeeper_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_zookeeper_cluster_ip $c1_zookeeper_cluster_ip

export c1_zookeeper_external_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_zookeeper_external_ip $c1_zookeeper_external_ip

export c1_zookeeper_pod_ip="$(kubectl get pod -n default --selector app=zookeeper -o jsonpath='{.items[0].status.podIP}')"
echo c1_zookeeper_pod_ip $c1_zookeeper_pod_ip

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
    name: zookeeper
EOF
###

### 2.3 创建 derive-local namespace

###bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"zookeeper"}}}'  --type=merge
###

### 2.4 部署 zookeeper connector(c1-zk-to-c1-derive-local)

###
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-zk-to-c1-derive-local
spec:
  httpAddr: $c1_zookeeper_cluster_ip:2181
  deriveNamespace: derive-local
  basePath: /Application/grpc
  category: providers
  adaptor: nebula
  asInternalServices: true
  syncToK8S:
    enable: true
  syncFromK8S:
    enable: false
EOF
###

### 2.7 部署 zookeeper 微服务

###bash
WITH_MESH=true fsm_cluster_name=c1 make deploy-zookeeper-nebula-grcp-server
WITH_MESH=true fsm_cluster_name=c1 make deploy-zookeeper-nebula-grcp-client
###