#!/bin/bash

# 场景 SmartDNS 业务测试

## 1 部署 K8S 集群

###bash
clusters="C1" agents=2 make k3d-up
###

## 2 部署 Eureka 集群

###bash
docker run -d --network fsm --ip 172.22.0.230 --rm --name smartdns-eureka -p 8761:8761 -t flomesh/samples-discovery-server:latest

#等待 eureka 服务启动
sleep 30s

docker run -d --network fsm --ip 172.22.0.231 --rm --name smartdns-eureka-httpbin-demo-1 -t cybwan/smartdns-eureka-httpbin-demo:latest java -Dotel.traces.exporter=none -Dotel.metrics.exporter=none -Dotel.propagators=tracecontext,baggage,b3multi -jar httpbin-eureka.jar

docker run -d --network fsm --ip 172.22.0.232 --rm --name smartdns-eureka-httpbin-demo-2 -t cybwan/smartdns-eureka-httpbin-demo:latest java -Dotel.traces.exporter=none -Dotel.metrics.exporter=none -Dotel.propagators=tracecontext,baggage,b3multi -jar httpbin-eureka.jar
###

## 3 部署 Nacos 集群

###bash
docker run -d --network fsm --ip 172.22.0.220 --rm -e MODE=standalone --name smartdns-nacos -p 8848:8848 -t nacos/nacos-server:v2.3.0

#等待 nacos 服务启动
sleep 30s

docker run -d --network fsm --ip 172.22.0.221 --rm --name smartdns-nacos-httpbin-demo-1 -t cybwan/smartdns-nacos-httpbin-demo:latest java -Dotel.traces.exporter=none -Dotel.metrics.exporter=none -Dotel.propagators=tracecontext,baggage,b3multi -jar httpbin-nacos.jar

docker run -d --network fsm --ip 172.22.0.222 --rm --name smartdns-nacos-httpbin-demo-2 -t cybwan/smartdns-nacos-httpbin-demo:latest java -Dotel.traces.exporter=none -Dotel.metrics.exporter=none -Dotel.propagators=tracecontext,baggage,b3multi -jar httpbin-nacos.jar
###

## 4 部署网格服务

###bash
kubecm switch k3d-C1
fsm_cluster_name=C1 sidecar=NodeLevel k3s=true mesh=true e4lb=true make deploy-fsm
###

## 5 部署 fgw

###bash
kubectl apply -n fsm-system -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: dns-proxy
spec:
  gatewayClassName: fsm
  listeners:
    - protocol: UDP
      port: 10053
      name: internal-dns
      allowedRoutes:
        namespaces:
          from: All
    - protocol: UDP
      port: 53
      name: external-dns
      allowedRoutes:
        namespaces:
          from: All
EOF

sleep 3

kubectl patch daemonset fsm-gateway-fsm-system-dns-proxy -n fsm-system -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"k3d-c1-server-0"}}}}}'  --type=merge

kubectl wait --all --for=condition=ready pod -n fsm-system -l app=fsm-gateway --timeout=180s

until kubectl get service/fsm-gateway-fsm-system-dns-proxy-udp -n fsm-system --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

export c1_fgw_cluster_ip="$(kubectl get svc -n fsm-system --field-selector metadata.name=fsm-gateway-fsm-system-dns-proxy-udp -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_fgw_cluster_ip $c1_fgw_cluster_ip

export c1_fgw_external_ip="$(kubectl get svc -n fsm-system --field-selector metadata.name=fsm-gateway-fsm-system-dns-proxy-udp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_fgw_external_ip $c1_fgw_external_ip

export c1_fgw_pod_ip="$(kubectl get pod -n fsm-system --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo c1_fgw_pod_ip $c1_fgw_pod_ip
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
kubectl apply  -f - <<EOF
kind: EurekaConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: to-c1-eureka
spec:
  httpAddr: http://172.22.0.230:8761/eureka
  deriveNamespace: eureka
  asInternalServices: true
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
kubectl apply  -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: to-c1-nacos
spec:
  httpAddr: 172.22.0.220:8848
  deriveNamespace: nacos
  asInternalServices: true
  syncToK8S:
    enable: true
  syncFromK8S:
    enable: false
EOF
###

## 3 E4LB 业务测试

### 3.1 部署模拟业务服务

###bash
WITH_MESH=false replicas=3 make deploy-hostname-httpbin
###

### 3.2 配置 EIP

###bash
kubectl apply -n demo -f - <<EOF
kind: EIPAdvertisement
apiVersion: xnetwork.flomesh.io/v1alpha1
metadata:
  name: demo
spec:
  service:
    name: httpbin
  eip: 172.22.0.188
  nodes:
  - k3d-c1-server-0
EOF
###

##注:##

- ##如果没有设置 nodes,则遵循 3.2.1.1 的规则##

### 3.3 部署模拟外部客户端

###bash
docker run -d --network fsm --rm --name e4lb-client -t cybwan/curl:latest sleep 1h
###