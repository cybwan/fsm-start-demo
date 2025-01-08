#!/bin/bash

# 场景 DNS 业务测试

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

## 3 DNS 业务测试

### 3.1 部署 DNS 模拟服务

####所有域名都解析为 1.1.1.1##

###bash
kubectl create namespace mesh-in
fsm namespace add mesh-in
kubectl apply -n mesh-in -f manifests/curl.yaml
sleep 2
kubectl wait --all --for=condition=ready pod -n mesh-in -l app=curl --timeout=180s

kubectl create namespace dns
kubectl apply -n dns -f manifests/dns.yaml
sleep 2
kubectl wait --all --for=condition=ready pod -n dns -l app=dns --timeout=180s
export dns_svc_ip="$(kubectl get svc -n dns dns -o jsonpath='{.spec.clusterIP}')"
echo $dns_svc_ip
###

### 3.2 配置 XNET DNS策略

###bash
export xnetwork_pod=$(kubectl get pods --selector app=fsm-xnetwork -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $1}')
#禁用 UDP 默认放行策略
kubectl exec $xnetwork_pod -n fsm-system -c fsm-xnet -- xnat cfg set --ipv4_udp_proto_allow_all=0
#启用 UDP 按端口转发
kubectl exec $xnetwork_pod -n fsm-system -c fsm-xnet -- xnat cfg set --ipv4_udp_nat_by_port_on=1

#配置 DNS 转发策略
export cni0_mac=$(kubectl exec $xnetwork_pod -n fsm-system -c fsm-xnet -- ip l show dev cni0 | grep 'link/ether '| awk '{print $2}')
kubectl exec $xnetwork_pod -n fsm-system -c fsm-xnet -- bash -c "xnat nat add --addr=0.0.0.0 --port=53 --proto-udp --tc-ingress --ep-addr=$dns_svc_ip --ep-port=1153 --ep-mac=$cni0_mac"
kubectl exec $xnetwork_pod -n fsm-system -c fsm-xnet -- bash -c "xnat nat add --addr=0.0.0.0 --port=53 --proto-udp --tc-egress  --ep-addr=$dns_svc_ip --ep-port=1153 --ep-mac=$cni0_mac"
###