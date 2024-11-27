#!/bin/bash

# 场景 Consul & K8S 跨集群混合架构微服务融合
## 1 部署 C1 C2 C3 三个集群
export clusters="C1 C2 C3"
make k3d-up

## 2 部署服务
### 2.1 C1集群
kubecm switch k3d-C1

#### 2.1.1 部署 FSM Mesh
fsm_cluster_name=C1 make deploy-fsm

#### 2.1.2 部署 K8S 微服务
WITH_MESH=true make deploy-bookwarehouse

### 2.2 C2集群
kubecm switch k3d-C2

#### 2.2.1 部署 FSM Mesh
fsm_cluster_name=C2 make deploy-fsm

#### 2.2.2 部署 Consul 微服务
make consul-deploy

PORT_FORWARD="8502:8500" make consul-port-forward &

export c2_consul_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=consul -o jsonpath='{.items[0].spec.clusterIP}')"
echo c2_consul_cluster_ip $c2_consul_cluster_ip

export c2_consul_external_ip="$(kubectl get svc -n default --field-selector metadata.name=consul -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c2_consul_external_ip $c2_consul_external_ip

export c2_consul_pod_ip="$(kubectl get pod -n default --selector app=consul -o jsonpath='{.items[0].status.podIP}')"
echo c2_consul_pod_ip $c2_consul_pod_ip

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
    name: consul
EOF

WITH_MESH=true make deploy-consul-bookstore

### 2.3 C3集群
kubecm switch k3d-C3

#### 2.3.1 部署 FSM Mesh
fsm_cluster_name=C3 make deploy-fsm

#### 2.3.2 部署 Consul 微服务
make consul-deploy

PORT_FORWARD="8503:8500" make consul-port-forward &

export c3_consul_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=consul -o jsonpath='{.items[0].spec.clusterIP}')"
echo c3_consul_cluster_ip $c3_consul_cluster_ip

export c3_consul_external_ip="$(kubectl get svc -n default --field-selector metadata.name=consul -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c3_consul_external_ip $c3_consul_external_ip

export c3_consul_pod_ip="$(kubectl get pod -n default --selector app=consul -o jsonpath='{.items[0].status.podIP}')"
echo c3_consul_pod_ip $c3_consul_pod_ip

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
    name: consul
EOF

WITH_MESH=true make deploy-consul-bookbuyer

## 3 微服务融合
### 3.1 C1 集群
kubecm switch k3d-C1

#### 3.1.1 部署 fgw
export fsm_namespace=fsm-system
kubectl apply -n "$fsm_namespace" -f - <<EOF
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
EOF

kubectl wait --all --for=condition=ready pod -n "$fsm_namespace" -l app=fsm-gateway --timeout=180s

until kubectl get service/fsm-gateway-fsm-system-k8s-c1-fgw-tcp -n $fsm_namespace --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

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
    namespace: fsm-system
    name: fsm-gateway-fsm-system-k8s-c1-fgw-tcp
EOF

export c1_fgw_cluster_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c1-fgw-tcp -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_fgw_cluster_ip $c1_fgw_cluster_ip

export c1_fgw_external_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c1-fgw-tcp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_fgw_external_ip $c1_fgw_external_ip

export c1_fgw_pod_ip="$(kubectl get pod -n $fsm_namespace --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo c1_fgw_pod_ip $c1_fgw_pod_ip

#### 3.1.2 部署 fgw connector
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
  egress:
    ipSelector: ClusterIP
    httpPort: 10090
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - bookwarehouse
EOF

#### 3.1.3 创建 derive-consul namespace
kubectl create namespace derive-consul
fsm namespace add derive-consul
kubectl patch namespace derive-consul -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"consul"}}}'  --type=merge

#### 3.1.4 部署 consul connector(c1-k8s-to-c2-consul)
kubectl apply  -f - <<EOF
kind: ConsulConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-k8s-to-c2-consul
spec:
  httpAddr: $c2_consul_external_ip:8500
  deriveNamespace: derive-consul
  syncToK8S:
    enable: false
  syncFromK8S:
    enable: true
    withGateway:
      enable: true
    allowK8sNamespaces:
      - bookwarehouse
EOF

### 3.2 C2 集群
kubecm switch k3d-C2

#### 3.2.1 部署 fgw
export fsm_namespace=fsm-system
kubectl apply -n "$fsm_namespace" -f - <<EOF
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
EOF

kubectl wait --all --for=condition=ready pod -n "$fsm_namespace" -l app=fsm-gateway --timeout=180s

until kubectl get service/fsm-gateway-fsm-system-k8s-c2-fgw-tcp -n $fsm_namespace --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

kubectl patch AccessControl -n fsm-policy global --type=json -p='[{"op": "add", "path": "/spec/sources/-", "value": {"kind":"Service","namespace":"fsm-system","name":"fsm-gateway-fsm-system-k8s-c2-fgw-tcp"}}]'

export c2_fgw_cluster_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c2-fgw-tcp -o jsonpath='{.items[0].spec.clusterIP}')"
echo c2_fgw_cluster_ip $c2_fgw_cluster_ip

export c2_fgw_external_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c2-fgw-tcp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c2_fgw_external_ip $c2_fgw_external_ip

export c2_fgw_pod_ip="$(kubectl get pod -n $fsm_namespace --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo c2_fgw_pod_ip $c2_fgw_pod_ip

#### 3.2.2 部署 fgw connector
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
  egress:
    ipSelector: ClusterIP
    httpPort: 10090
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - derive-consul
EOF

#### 3.2.3 创建 derive-consul namespace
kubectl create namespace derive-consul
fsm namespace add derive-consul
kubectl patch namespace derive-consul -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"consul"}}}'  --type=merge

#### 3.2.4 部署 consul connector(c2-consul-to-c2-derive-consul)
kubectl apply  -f - <<EOF
kind: ConsulConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c2-consul-to-c2-derive-consul
spec:
  httpAddr: $c2_consul_cluster_ip:8500
  deriveNamespace: derive-consul
  asInternalServices: true
  syncToK8S:
    enable: true
    withGateway:
      enable: true
  syncFromK8S:
    enable: false
EOF

#### 3.2.5 部署 consul connector(c2-k8s-to-c3-consul)
kubectl apply  -f - <<EOF
kind: ConsulConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c2-k8s-to-c3-consul
spec:
  httpAddr: $c3_consul_external_ip:8500
  deriveNamespace: none
  syncToK8S:
    enable: false
  syncFromK8S:
    enable: true
    withGateway:
      enable: true
    allowK8sNamespaces:
      - derive-consul
EOF

### 3.3 C3 集群
kubecm switch k3d-C3

#### 3.3.1 部署 fgw
export fsm_namespace=fsm-system
kubectl apply -n "$fsm_namespace" -f - <<EOF
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
EOF

kubectl wait --all --for=condition=ready pod -n "$fsm_namespace" -l app=fsm-gateway --timeout=180s

until kubectl get service/fsm-gateway-fsm-system-k8s-c3-fgw-tcp -n $fsm_namespace --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

kubectl patch AccessControl -n fsm-policy global --type=json -p='[{"op": "add", "path": "/spec/sources/-", "value": {"kind":"Service","namespace":"fsm-system","name":"fsm-gateway-fsm-system-k8s-c3-fgw-tcp"}}]'

export c3_fgw_cluster_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c3-fgw-tcp -o jsonpath='{.items[0].spec.clusterIP}')"
echo c3_fgw_cluster_ip $c3_fgw_cluster_ip

export c3_fgw_external_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c3-fgw-tcp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c3_fgw_external_ip $c3_fgw_external_ip

export c3_fgw_pod_ip="$(kubectl get pod -n $fsm_namespace --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo c3_fgw_pod_ip $c3_fgw_pod_ip

#### 3.3.2 部署 fgw connector
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
  egress:
    ipSelector: ClusterIP
    httpPort: 10090
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - derive-consul
EOF

#### 3.3.3 创建 derive-consul namespace
kubectl create namespace derive-consul
fsm namespace add derive-consul
kubectl patch namespace derive-consul -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"consul"}}}'  --type=merge

#### 3.3.4 部署 consul connector(c3-consul-to-c3-derive-consul)
kubectl apply  -f - <<EOF
kind: ConsulConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c3-consul-to-c3-derive-consul
spec:
  httpAddr: $c3_consul_cluster_ip:8500
  deriveNamespace: derive-consul
  asInternalServices: true
  syncToK8S:
    enable: true
    withGateway:
      enable: true
  syncFromK8S:
    enable: false
EOF

## 4 确认服务调用效果
kubecm switch k3d-C3

PORT_FORWARD="14003:14001" make bookbuyer-port-forward &

echo
echo c2_consul_cluster_ip $c2_consul_cluster_ip
echo c2_consul_external_ip $c2_consul_external_ip
echo c2_consul_pod_ip $c2_consul_pod_ip

echo
echo c3_consul_cluster_ip $c3_consul_cluster_ip
echo c3_consul_external_ip $c3_consul_external_ip
echo c3_consul_pod_ip $c3_consul_pod_ip

echo
echo c1_fgw_cluster_ip $c1_fgw_cluster_ip
echo c1_fgw_external_ip $c1_fgw_external_ip
echo c1_fgw_pod_ip $c1_fgw_pod_ip

echo
echo c2_fgw_cluster_ip $c2_fgw_cluster_ip
echo c2_fgw_external_ip $c2_fgw_external_ip
echo c2_fgw_pod_ip $c2_fgw_pod_ip

echo
echo c3_fgw_cluster_ip $c3_fgw_cluster_ip
echo c3_fgw_external_ip $c3_fgw_external_ip
echo c3_fgw_pod_ip $c3_fgw_pod_ip

echo
echo