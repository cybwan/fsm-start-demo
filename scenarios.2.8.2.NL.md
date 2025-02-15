# 场景 SmartDNS & Calico & vxlan 业务测试

## 1 部署 K8S 集群

### 1.1 组件要求

**k8s + metallb + calico vxlan**

### 1.2 节点网络配置

#### 1.2.1 master

```yaml
# This is the network config written by 'subiquity'
network:
  ethernets:
    ens36:
      dhcp4: false
      addresses: [192.168.226.80/24,A192:A168:A226::80/64]
    ens33:
      dhcp4: false
      mtu: 1436
      addresses: [192.168.127.80/24,B192:B168:B127::80/64]
      nameservers:
        addresses: [8.8.8.8]
      routes:
      - to: default
        via: 192.168.127.1
      - to: 11.11.0.0/24
        via: 192.168.127.51
      - to: 22.22.0.0/24
        via: 192.168.127.52
  version: 2
```

#### 1.2.2 worker1

```yaml
# This is the network config written by 'subiquity'
network:
  ethernets:
    ens36:
      dhcp4: false
      addresses: [192.168.226.81/24,A192:A168:A226::81/64]
    ens33:
      dhcp4: false
      mtu: 1436
      addresses: [192.168.127.81/24,B192:B168:B127::81/64]
      nameservers:
        addresses: [8.8.8.8]
      routes:
      - to: default
        via: 192.168.127.1
      - to: 11.11.0.0/24
        via: 192.168.127.51
      - to: 22.22.0.0/24
        via: 192.168.127.52
  version: 2
```

#### 1.2.3 worker2

```yaml
# This is the network config written by 'subiquity'
network:
  ethernets:
    ens36:
      dhcp4: false
      addresses: [192.168.226.82/24,A192:A168:A226::82/64]
    ens33:
      dhcp4: false
      mtu: 1436
      addresses: [192.168.127.82/24,B192:B168:B127::82/64]
      nameservers:
        addresses: [8.8.8.8]
      routes:
      - to: default
        via: 192.168.127.1
      - to: 11.11.0.0/24
        via: 192.168.127.51
      - to: 22.22.0.0/24
        via: 192.168.127.52
  version: 2
```

## 2 部署 Eureka 集群

### 2.1 Eureka节点网络配置

```yaml
# This is the network config written by 'subiquity'
network:
  ethernets:
    ens36:
      dhcp4: false
      addresses: [192.168.226.51/24,A192:A168:A226::51/64]
    ens33:
      dhcp4: false
      mtu: 1436
      addresses: [192.168.127.51/24,B192:B168:B127::51/64]
      nameservers:
        addresses: [8.8.8.8]
      routes:
      - to: default
        via: 192.168.127.1
  version: 2
```

### 2.2 Eureka服务部署

```bash
if ! docker network ls --format "{{ .Name}}" | grep -q eureka; then docker network create --driver=bridge --subnet=11.11.0.0/16 --gateway=11.11.0.1 eureka; fi

docker run -d --restart always --network eureka --ip 11.11.0.110 --name smartdns-eureka -p 8761:8761 -t flomesh/samples-discovery-server:latest

docker run -d --restart always --hostname demo1.httpbin.eureka.smartdns.local --network eureka --ip 11.11.0.111 -e EUREKA_SERVICE_URL=http://11.11.0.110:8761/eureka/ --name smartdns-eureka-httpbin-demo-1 -t cybwan/smartdns-eureka-httpbin-demo:latest java -Dotel.traces.exporter=none -Dotel.metrics.exporter=none -Dotel.propagators=tracecontext,baggage,b3multi -jar httpbin-eureka.jar

docker run -d --restart always --hostname demo2.httpbin.eureka.smartdns.local --network eureka --ip 11.11.0.112 -e EUREKA_SERVICE_URL=http://11.11.0.110:8761/eureka/ --name smartdns-eureka-httpbin-demo-2 -t cybwan/smartdns-eureka-httpbin-demo:latest java -Dotel.traces.exporter=none -Dotel.metrics.exporter=none -Dotel.propagators=tracecontext,baggage,b3multi -jar httpbin-eureka.jar
```

## 3 部署 Nacos 集群

### 2.1 Nacos节点网络配置

```yaml
# This is the network config written by 'subiquity'
network:
  ethernets:
    ens36:
      dhcp4: false
      addresses: [192.168.226.52/24,A192:A168:A226::52/64]
    ens33:
      dhcp4: false
      mtu: 1436
      addresses: [192.168.127.52/24,B192:B168:B127::52/64]
      nameservers:
        addresses: [8.8.8.8]
      routes:
      - to: default
        via: 192.168.127.1
  version: 2
```

### 3.2 Nacos服务部署

```bash
if ! docker network ls --format "{{ .Name}}" | grep -q nacos; then docker network create --driver=bridge --subnet=22.22.0.0/16 --gateway=22.22.0.1 nacos; fi

docker run -d --restart always --network nacos --ip 22.22.0.220 -e MODE=standalone --name smartdns-nacos -p 8848:8848 -p 9848:9848 -t nacos/nacos-server:v2.3.0

docker run -d --restart always --hostname demo1.httpbin.nacos.smartdns.local --network nacos --ip 22.22.0.221 -e NACOS_SERVICE_URL=22.22.0.220:8848 --name smartdns-nacos-httpbin-demo-1 -t cybwan/smartdns-nacos-httpbin-demo:latest java -Dotel.traces.exporter=none -Dotel.metrics.exporter=none -Dotel.propagators=tracecontext,baggage,b3multi -jar httpbin-nacos.jar

docker run -d --restart always --hostname demo2.httpbin.nacos.smartdns.local --network nacos --ip 22.22.0.222 -e NACOS_SERVICE_URL=22.22.0.220:8848 --name smartdns-nacos-httpbin-demo-2 -t cybwan/smartdns-nacos-httpbin-demo:latest java -Dotel.traces.exporter=none -Dotel.metrics.exporter=none -Dotel.propagators=tracecontext,baggage,b3multi -jar httpbin-nacos.jar
```

## 4 部署SmartDNS服务

```bash
export CTR_REGISTRY=cybwan
export PIPY_REGISTRY=flomesh
export CTR_TAG=1.5.0-alpha.15

fsm_cluster_name=C1 sidecar=NodeLevel k8s=true mesh=true e4lb=true e4lb_cni=calicoVxlan make deploy-smartdns
```

## 5 部署 FGW DNS Proxy

### 5.1 部署 FGW

```bash
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

kubectl patch daemonset fsm-gateway-fsm-system-fgw-dns-proxy -n fsm-system -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"worker1"}}}}}'  --type=merge
```

### 5.2 配置 INGRESS 方向 DNS filter

```bash
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
```

### 5.3 配置 EGRESS 方向 DNS filter

```bash
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
```

## 6 导入 Eureka 服务

### 6.1 创建 derive-eureka namespace

```bash
kubectl create namespace eureka
fsm namespace add eureka
kubectl patch namespace eureka -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"eureka"}}}'  --type=merge
```

### 6.2 部署 eureka connector

```
kubectl apply  -f - <<EOF
kind: EurekaConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: to-c1-eureka
spec:
  httpAddr: http://192.168.127.51:8761/eureka
  deriveNamespace: eureka
  asInternalServices: true
  syncToK8S:
    enable: true
  syncFromK8S:
    enable: false
EOF
```

## 7 导入 Nacos 服务

### 7.1 创建 derive-nacos namespace

```bash
kubectl create namespace nacos
fsm namespace add nacos
kubectl patch namespace nacos -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"nacos"}}}'  --type=merge
```

### 7.2 部署 nacos connector

```
kubectl apply  -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: to-c1-nacos
spec:
  httpAddr: 192.168.127.52:8848
  deriveNamespace: nacos
  asInternalServices: true
  syncToK8S:
    enable: true
  syncFromK8S:
    enable: false
EOF
```

## 8 E4LB 业务测试

### 8.1 demo/httpbin 配置 EIP

```bash
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
  - worker2
EOF
```

### 8.2 eureka/httpbin 配置 EIP

```bash
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
  - worker2
EOF
```

### 8.3 nacos/httpbin 配置 EIP

```bash
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
  - worker2
EOF
```

### 8.4 业务功能测试

#### 8.4.1 K8S集群外经 EIP 访问 K8S 内微服务

##### 8.4.1.1 demo/httpbin 调用效果

多次执行:

```bash
curl -s 192.168.127.186:80
```

返回结果如下:

```bash
hi, I am httpbin from host: httpbin-84dc4dcffd-hqbzr at node: worker1 by pipy!
hi, I am httpbin from host: httpbin-84dc4dcffd-dnsq4 at node: worker2 by pipy!
```

调用效果是分别从两个服务实例返回.

#### 8.4.2 K8S集群外经 EIP 访问跨网段 Eureka 微服务

##### 8.4.2.1 eureka/httpbin 调用效果

多次执行:

```bash
curl -s 192.168.127.187:14001
```

返回结果如下:

```bash
demo1.httpbin.eureka.smartdns.local
demo2.httpbin.eureka.smartdns.local
```

#### 8.4.3 K8S集群外经 EIP 访问跨网段 Nacos 微服务

##### 8.4.3.1 nacos/httpbin 调用效果

多次执行:

```bash
curl -s 192.168.127.188:14001
```

返回结果如下:

```bash
demo1.httpbin.nacos.smartdns.local
demo2.httpbin.nacos.smartdns.local
```

#### 8.4.4 K8S集群内域名解析测试

##### 8.4.4.1 部署被 FSM 管控的模拟业务

```bash
kubectl create namespace curl
fsm namespace add curl
kubectl apply -n curl -f ./manifests/native/curl.yaml
```

##### 8.4.4.2  解析 google.com 域名

执行:

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -- nslookup google.com
```

返回结果如下:

```bash
Server:		10.96.0.10
Address:	10.96.0.10:53

Non-authoritative answer:
Name:	google.com
Address: 11.11.11.11

Non-authoritative answer:
Name:	google.com
Address: 11.11.11.11
```
