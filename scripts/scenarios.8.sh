#!/bin/bash
# 场景 Eureka 跨集群微服务融合

## 1 部署 C1 C2 两个集群

#bash
export clusters="C1 C2"
make k3d-up
#

## 2 部署服务

### 2.1 C1集群

#bash
kubecm switch k3d-C1
#

#### 2.1.1 部署 FSM Mesh

#bash
fsm_cluster_name=C1 make deploy-fsm
#

#### 2.1.2 部署 Eureka 微服务

#bash
make eureka-deploy

PORT_FORWARD="8701:8761" make eureka-port-forward &

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

WITH_MESH=true make deploy-eureka-bookstore
#

### 2.2 C2集群

#bash
kubecm switch k3d-C2
#

#### 2.2.1 部署 Eureka 微服务

#bash
make eureka-deploy

PORT_FORWARD="8702:8761" make eureka-port-forward &

export c2_eureka_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=eureka -o jsonpath='{.items[0].spec.clusterIP}')"
echo c2_eureka_cluster_ip $c2_eureka_cluster_ip

export c2_eureka_external_ip="$(kubectl get svc -n default --field-selector metadata.name=eureka -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c2_eureka_external_ip $c2_eureka_external_ip

export c2_eureka_pod_ip="$(kubectl get pod -n default --selector app=eureka -o jsonpath='{.items[0].status.podIP}')"
echo c2_eureka_pod_ip $c2_eureka_pod_ip
#

## 3 微服务融合

### 3.1 C1 集群

#bash
kubecm switch k3d-C1
#

#### 3.1.1 部署 fgw

#bash
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

kubectl patch AccessControl -n fsm-policy global --type=json -p='[{"op": "add", "path": "/spec/sources/-", "value": {"kind":"Service","namespace":"fsm-system","name":"fsm-gateway-fsm-system-k8s-c1-fgw-tcp"}}]'

export c1_fgw_cluster_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c1-fgw-tcp -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_fgw_cluster_ip $c1_fgw_cluster_ip

export c1_fgw_external_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c1-fgw-tcp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_fgw_external_ip $c1_fgw_external_ip

export c1_fgw_pod_ip="$(kubectl get pod -n $fsm_namespace --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo c1_fgw_pod_ip $c1_fgw_pod_ip
#

#### 3.1.2 部署 fgw connector

#bash
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
      - derive-eureka
EOF
#

#### 3.1.3 创建 derive-eureka namespace

#bash
kubectl create namespace derive-eureka
fsm namespace add derive-eureka
kubectl patch namespace derive-eureka -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"eureka"}}}'  --type=merge
#

#### 3.1.4 部署 eureka connector(c1-eureka-to-c1-derive-eureka)

#
kubectl apply  -f - <<EOF
kind: EurekaConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-eureka-to-c1-derive-eureka
spec:
  httpAddr: http://$c1_eureka_cluster_ip:8761/eureka
  deriveNamespace: derive-eureka
  asInternalServices: true
  syncToK8S:
    enable: true
    withGateway: 
      enable: true
  syncFromK8S:
    enable: false
EOF
#

#### 3.1.5 部署 eureka connector(c1-fgw-to-c2-eureka)

#
kubectl patch service fsm-bootstrap -n fsm-system -p '{"metadata":{"annotations":{"flomesh.io/service-sync-k8s-to-cloud":"false"}}}'  --type=merge
kubectl patch service fsm-controller -n fsm-system -p '{"metadata":{"annotations":{"flomesh.io/service-sync-k8s-to-cloud":"false"}}}'  --type=merge
kubectl patch service fsm-injector -n fsm-system -p '{"metadata":{"annotations":{"flomesh.io/service-sync-k8s-to-cloud":"false"}}}'  --type=merge
kubectl patch service fsm-validator -n fsm-system -p '{"metadata":{"annotations":{"flomesh.io/service-sync-k8s-to-cloud":"false"}}}'  --type=merge

kubectl patch service fsm-gateway-fsm-system-k8s-c1-fgw-tcp -n fsm-system -p '{"metadata":{"annotations":{"flomesh.io/service-port":"10080"}}}'  --type=merge

kubectl apply  -f - <<EOF
kind: EurekaConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-fgw-to-c2-eureka
spec:
  httpAddr: http://$c2_eureka_external_ip:8761/eureka
  deriveNamespace: none
  syncToK8S:
    enable: false
  syncFromK8S:
    enable: true
    withGateway: 
      enable: false
    allowK8sNamespaces:
      - fsm-system
    syncClusterIPServices: false
    syncLoadBalancerEndpoints: false
EOF
#

### 3.2 C2 集群

#bash
kubecm switch k3d-C2
#

echo
echo c1_eureka_cluster_ip $c1_eureka_cluster_ip
echo c1_eureka_external_ip $c1_eureka_external_ip
echo c1_eureka_pod_ip $c1_eureka_pod_ip

echo
echo c2_eureka_cluster_ip $c2_eureka_cluster_ip
echo c2_eureka_external_ip $c2_eureka_external_ip
echo c2_eureka_pod_ip $c2_eureka_pod_ip

echo
echo c1_fgw_cluster_ip $c1_fgw_cluster_ip
echo c1_fgw_external_ip $c1_fgw_external_ip
echo c1_fgw_pod_ip $c1_fgw_pod_ip