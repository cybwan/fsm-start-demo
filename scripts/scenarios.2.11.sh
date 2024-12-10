#!/bin/bash

# 场景 Nebula-GRPC 多集群微服务融合测试

## 1 部署 K8S 三个集群

###bash
clusters="C1 C2 C3" make k3d-up
###

## 2 部署服务

### 2.1 C1集群

###bash
kubecm switch k3d-C1
###

#### 2.1.1 部署网格服务

###bash
fsm_cluster_name=C1 sidecar=PodLevel make deploy-fsm
###

#### 2.1.2 部署 fgw

###bash
kubectl apply -n fsm-system -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: k8s-c1-fgw
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
      port: 10090
      name: egrs-http
      allowedRoutes:
        namespaces:
          from: All
    - protocol: HTTP
      port: 10081
      name: igrs-grpc
      allowedRoutes:
        namespaces:
          from: All
    - protocol: HTTP
      port: 10091
      name: egrs-grpc
      allowedRoutes:
        namespaces:
          from: All
EOF

sleep 3

kubectl wait --all --for=condition=ready pod -n fsm-system -l app=fsm-gateway --timeout=180s

until kubectl get service/fsm-gateway-fsm-system-k8s-c1-fgw-tcp -n fsm-system --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

export c1_fgw_cluster_ip="$(kubectl get svc -n fsm-system --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c1-fgw-tcp -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_fgw_cluster_ip $c1_fgw_cluster_ip

export c1_fgw_external_ip="$(kubectl get svc -n fsm-system --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c1-fgw-tcp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_fgw_external_ip $c1_fgw_external_ip

export c1_fgw_pod_ip="$(kubectl get pod -n fsm-system --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo c1_fgw_pod_ip $c1_fgw_pod_ip
###

#### 2.1.3 部署 zookeeper 服务

###bash
make zk-deploy

export c1_zookeeper_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_zookeeper_cluster_ip $c1_zookeeper_cluster_ip

export c1_zookeeper_external_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_zookeeper_external_ip $c1_zookeeper_external_ip

export c1_zookeeper_pod_ip="$(kubectl get pod -n default --selector app=zookeeper -o jsonpath='{.items[0].status.podIP}')"
echo c1_zookeeper_pod_ip $c1_zookeeper_pod_ip

#ZOOKEEPER_PORT_FORWARD=12181:2181 ZOOWEBUI_PORT_FORWARD=18081:8081 make zk-port-forward
###

#### 2.1.4 部署 zookeeper 服务访问控制策略

###bash
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
  - kind: Service
    namespace: fsm-system
    name: fsm-gateway-fsm-system-k8s-c1-fgw-tcp
EOF
###

#### 2.1.5 创建 derive-local namespace

###bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"zookeeper"}}}'  --type=merge
###

#### 2.1.6 部署 zookeeper connector(c1-zk-to-c1-derive-local)

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
    withGateway:
      enable: true
  syncFromK8S:
    enable: false
EOF
###

#### 2.1.7 部署 fgw connector

###bash
kubectl apply  -f - <<EOF
kind: GatewayConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-fgw
spec:
  gatewayName: k8s-c1-fgw
  ingress:
    ipSelector: ExternalIP
    httpPort: 10080
    grpcPort: 10081
  egress:
    ipSelector: ClusterIP
    httpPort: 10090
    grpcPort: 10091
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - derive-local
EOF
###

#### 2.1.8 部署 zookeeper 微服务

###bash
WITH_MESH=true fsm_cluster_name=c1 make deploy-zookeeper-nebula-grcp-server
###

### 2.2 C2集群

###bash
kubecm switch k3d-C2
###

#### 2.2.1 部署网格服务

###bash
fsm_cluster_name=C2 sidecar=PodLevel make deploy-fsm
###

#### 2.2.2 部署 fgw

###bash
kubectl apply -n fsm-system -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: k8s-c2-fgw
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
      port: 10090
      name: egrs-http
      allowedRoutes:
        namespaces:
          from: All
    - protocol: HTTP
      port: 10081
      name: igrs-grpc
      allowedRoutes:
        namespaces:
          from: All
    - protocol: HTTP
      port: 10091
      name: egrs-grpc
      allowedRoutes:
        namespaces:
          from: All
EOF

sleep 3

kubectl wait --all --for=condition=ready pod -n fsm-system -l app=fsm-gateway --timeout=180s

until kubectl get service/fsm-gateway-fsm-system-k8s-c2-fgw-tcp -n fsm-system --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

export c2_fgw_cluster_ip="$(kubectl get svc -n fsm-system --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c2-fgw-tcp -o jsonpath='{.items[0].spec.clusterIP}')"
echo c2_fgw_cluster_ip $c2_fgw_cluster_ip

export c2_fgw_external_ip="$(kubectl get svc -n fsm-system --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c2-fgw-tcp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c2_fgw_external_ip $c2_fgw_external_ip

export c2_fgw_pod_ip="$(kubectl get pod -n fsm-system --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo c2_fgw_pod_ip $c2_fgw_pod_ip
###

#### 2.2.3 部署 zookeeper 服务

###bash
make zk-deploy

export c2_zookeeper_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].spec.clusterIP}')"
echo c2_zookeeper_cluster_ip $c2_zookeeper_cluster_ip

export c2_zookeeper_external_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c2_zookeeper_external_ip $c2_zookeeper_external_ip

export c2_zookeeper_pod_ip="$(kubectl get pod -n default --selector app=zookeeper -o jsonpath='{.items[0].status.podIP}')"
echo c2_zookeeper_pod_ip $c2_zookeeper_pod_ip

#ZOOKEEPER_PORT_FORWARD=22181:2181 ZOOWEBUI_PORT_FORWARD=28081:8081 make zk-port-forward
###

#### 2.2.4 设置服务访问控制策略

###bash
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
  - kind: Service
    namespace: fsm-system
    name: fsm-gateway-fsm-system-k8s-c2-fgw-tcp
EOF
###

#### 2.2.5 创建 derive-local namespace

###bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"zookeeper"}}}'  --type=merge
###

#### 2.2.6 部署 zookeeper connector(c2-zk-to-c2-derive-local)

###
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c2-zk-to-c2-derive-local
spec:
  httpAddr: $c2_zookeeper_cluster_ip:2181
  deriveNamespace: derive-local
  basePath: /Application/grpc
  category: providers
  adaptor: nebula
  asInternalServices: true
  syncToK8S:
    enable: true
    withGateway:
      enable: true
  syncFromK8S:
    enable: false
EOF
###

#### 2.2.7 部署 fgw connector

###bash
kubectl apply  -f - <<EOF
kind: GatewayConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c2-fgw
spec:
  gatewayName: k8s-c2-fgw
  ingress:
    ipSelector: ExternalIP
    httpPort: 10080
    grpcPort: 10081
  egress:
    ipSelector: ClusterIP
    httpPort: 10090
    grpcPort: 10091
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - derive-local
EOF
###

#### 2.2.8 部署 zookeeper 微服务

###bash
WITH_MESH=true fsm_cluster_name=c2 make deploy-zookeeper-nebula-grcp-server
###

### 2.3 C3集群

###bash
kubecm switch k3d-C3
###

#### 2.3.1 部署网格服务

###bash
fsm_cluster_name=C3 sidecar=PodLevel make deploy-fsm
###

#### 2.3.2 部署 fgw

###bash
kubectl apply -n fsm-system -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: k8s-c3-fgw
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
      port: 10090
      name: egrs-http
      allowedRoutes:
        namespaces:
          from: All
    - protocol: HTTP
      port: 10081
      name: igrs-grpc
      allowedRoutes:
        namespaces:
          from: All
    - protocol: HTTP
      port: 10091
      name: egrs-grpc
      allowedRoutes:
        namespaces:
          from: All
EOF

sleep 3

kubectl wait --all --for=condition=ready pod -n fsm-system -l app=fsm-gateway --timeout=180s

until kubectl get service/fsm-gateway-fsm-system-k8s-c3-fgw-tcp -n fsm-system --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

export c3_fgw_cluster_ip="$(kubectl get svc -n fsm-system --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c3-fgw-tcp -o jsonpath='{.items[0].spec.clusterIP}')"
echo c3_fgw_cluster_ip $c3_fgw_cluster_ip

export c3_fgw_external_ip="$(kubectl get svc -n fsm-system --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c3-fgw-tcp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c3_fgw_external_ip $c3_fgw_external_ip

export c3_fgw_pod_ip="$(kubectl get pod -n fsm-system --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo c3_fgw_pod_ip $c3_fgw_pod_ip
###

#### 2.3.3 部署 zookeeper 服务

###bash
make zk-deploy

export c3_zookeeper_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].spec.clusterIP}')"
echo c3_zookeeper_cluster_ip $c3_zookeeper_cluster_ip

export c3_zookeeper_external_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c3_zookeeper_external_ip $c3_zookeeper_external_ip

export c3_zookeeper_pod_ip="$(kubectl get pod -n default --selector app=zookeeper -o jsonpath='{.items[0].status.podIP}')"
echo c3_zookeeper_pod_ip $c3_zookeeper_pod_ip

#ZOOKEEPER_PORT_FORWARD=32181:2181 ZOOWEBUI_PORT_FORWARD=38081:8081 make zk-port-forward
###

#### 2.3.4 设置服务访问控制策略

###bash
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
  - kind: Service
    namespace: fsm-system
    name: fsm-gateway-fsm-system-k8s-c3-fgw-tcp
EOF
###

#### 2.3.5 创建 derive-local namespace

###bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"zookeeper"}}}'  --type=merge
###

#### 2.3.6 部署 zookeeper connector(c3-zk-to-c3-derive-local)

###
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c3-zk-to-c3-derive-local
spec:
  httpAddr: $c3_zookeeper_cluster_ip:2181
  deriveNamespace: derive-local
  basePath: /Application/grpc
  category: providers
  adaptor: nebula
  asInternalServices: true
  syncToK8S:
    enable: true
    withGateway:
      enable: true
    filterIpRanges:
      - 10.103.1.0/24
  syncFromK8S:
    enable: false
EOF
###

#### 2.3.7 部署 fgw connector

###bash
kubectl apply  -f - <<EOF
kind: GatewayConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c3-fgw
spec:
  gatewayName: k8s-c3-fgw
  ingress:
    ipSelector: ExternalIP
    httpPort: 10080
    grpcPort: 10081
  egress:
    ipSelector: ClusterIP
    httpPort: 10090
    grpcPort: 10091
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - derive-local
      - derive-other
EOF
###

#### 2.3.8 部署 zookeeper 微服务

###bash
WITH_MESH=true fsm_cluster_name=c3 replicas=0 make deploy-zookeeper-nebula-grcp-server
WITH_MESH=true fsm_cluster_name=c3 make deploy-zookeeper-nebula-grcp-client
###

## 3 微服务融合

### 3.1 C1 集群

###bash
kubecm switch k3d-C1
###

#### 3.1.1 部署 zookeeper connector(c1-k8s-to-c3-zk)

##c1 k8s微服务同步到c3 zookeeper##

###
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-k8s-to-c3-zk
spec:
  httpAddr: $c3_zookeeper_external_ip:2181
  deriveNamespace: none
  basePath: /Application/grpc
  category: providers
  adaptor: nebula
  syncToK8S:
    enable: false
  syncFromK8S:
    enable: true
    withGateway:
      enable: true
    allowK8sNamespaces:
      - derive-local
EOF
###

### 3.2 C2 集群

###bash
kubecm switch k3d-C2
###

#### 3.2.1 部署 zookeeper connector(c2-k8s-to-c3-zk)

##c2 k8s微服务同步到c3 zookeeper##

###
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c2-k8s-to-c3-zk
spec:
  httpAddr: $c3_zookeeper_external_ip:2181
  deriveNamespace: none
  basePath: /Application/grpc
  category: providers
  adaptor: nebula
  syncToK8S:
    enable: false
  syncFromK8S:
    enable: true
    withGateway:
      enable: true
    allowK8sNamespaces:
      - derive-local
EOF
###

### 3.3 C3 集群

###bash
kubecm switch k3d-C3
###

#### 3.3.3 导入其他集群 zookeeper 微服务

##### 3.3.3.1 创建 derive-other namespace

###bash
kubectl create namespace derive-other
fsm namespace add derive-other
kubectl patch namespace derive-other -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"zookeeper"}}}'  --type=merge

kubectl patch namespace derive-other -p '{"metadata":{"annotations":{"flomesh.io/cloud-service-attached-to":"derive-local"}}}'  --type=merge
###

##### 3.3.3.2 部署 zookeeper connector(c3-zk-to-c3-derive-other)

###
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c3-zk-to-c3-derive-other
spec:
  httpAddr: $c3_zookeeper_cluster_ip:2181
  deriveNamespace: derive-other
  asInternalServices: false
  basePath: /Application/grpc
  category: providers
  adaptor: nebula
  syncToK8S:
    enable: true
    excludeIpRanges:
      - 10.103.1.0/24
    withGateway:
      enable: true
  syncFromK8S:
    enable: false
EOF
###