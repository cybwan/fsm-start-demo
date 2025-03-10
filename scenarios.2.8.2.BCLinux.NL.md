# 场景 SmartDNS & Calico & vxlan 业务测试

## 1 部署 K8S 集群

### 1.1 组件要求

**bclinux + k8s + metallb + calico vxlan**

### 1.2 节点网络配置

#### 1.2.1 master.bc

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

#### 1.2.2 worker1.bc

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

#### 1.2.3 worker2.bc

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
      addresses: [192.168.226.53/24,A192:A168:A226::53/64]
    ens33:
      dhcp4: false
      mtu: 1436
      addresses: [192.168.127.53/24,B192:B168:B127::53/64]
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
      addresses: [192.168.226.54/24,A192:A168:A226::54/64]
    ens33:
      dhcp4: false
      mtu: 1436
      addresses: [192.168.127.54/24,B192:B168:B127::54/64]
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

## 4 部署 SmartDNS 服务

```bash
export CTR_REGISTRY=172.168.226.1:5000/flomesh
export PIPY_REGISTRY=172.168.226.1:5000/flomesh
export CTR_XNET_REGISTRY=172.168.226.1:5000/flomesh
export CTR_TAG=latest
export CTR_XNET_TAG=bclinux-euler-22.10-latest

fsm_cluster_name=C1 sidecar=NodeLevel k8s=true mesh=true e4lb=true e4lb_cni=calicoVxlan make deploy-smartdns

# 无须 injector, 删除 injector
kubectl delete deployments.apps -n fsm-system fsm-injector
```

## 5 部署 SmartDNS FGW 服务

### 5.1 部署 FGW

```bash
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
```

### 5.2 配置 INGRESS 方向 DNS filter

```bash
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
spec:
  zones:
    global:
      domains:
        - name: google.com
          answer:
            rdata: 11.11.11.11
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
```

### 5.3 配置 EGRESS 方向 DNS filter

```bash
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
spec:
  zones:
    global:
      domains:
        - name: google.com
          answer:
            rdata: 22.22.22.22
    tenant-liaoning:
      domains:
        - name: httpbin.demo.global
          answer:
            rdata: 192.168.127.186
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
```

### 5.4 SmartDNS UDPRoute 授权

```bash
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
```

## 6 创建租户

### 6.1 创建租户空间

```bash
kubectl create namespace tenant-liaoning
```

### 6.2 部署模拟业务

```bash
kubectl apply -n tenant-liaoning -f ./manifests/native/curl.yaml
```

## 7 导入租户 Eureka 服务

### 7.1 部署 eureka connector

```
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
```

### 7.2 查看 eureka 上的服务

```bash
kubectl get eurekaconnector -n tenant-liaoning eureka-to-tenant-liaoning -o jsonpath='{.status.catalogServices}' | jq
```

返回结果如下:

```json
[
  {
    "service": "httpbin"
  }
]
```

### 7.3 导入 eureka 上的服务

```bash
kubectl get eurekaconnector -n tenant-liaoning eureka-to-tenant-liaoning -o json | jq '.spec.syncToK8S.conversionStrategy.serviceConversions += [{"service": "httpbin", "convertName": "httpbin-eureka", "externalName": "httpbin-eureka.liaoning.tenant"}]' | kubectl apply -f -
```

### 7.4 查看已经导入的服务

```bash
kubectl get service httpbin-eureka -n tenant-liaoning -o yaml
```

返回结果如下:

```yaml
apiVersion: v1
kind: Service
metadata:
  annotations:
    flomesh.io/cloud-endpoint-addr: eyJwb3J0cyI6eyIxNDAwMSI6Imh0dHAifSwiZW5kcG9pbnRzIjp7IjExLjExLjAuMTExIjp7InBvcnRzIjp7IjE0MDAxIjoiaHR0cCJ9LCJhZGRyZXNzIjoiMTEuMTEuMC4xMTEiLCJuYXRpdmUiOnsidmlhR2F0ZXdheU1vZGUiOiJmb3J3YXJkIn0sImxvY2FsIjp7fX0sIjExLjExLjAuMTEyIjp7InBvcnRzIjp7IjE0MDAxIjoiaHR0cCJ9LCJhZGRyZXNzIjoiMTEuMTEuMC4xMTIiLCJuYXRpdmUiOnsidmlhR2F0ZXdheU1vZGUiOiJmb3J3YXJkIn0sImxvY2FsIjp7fX19fQ==
    flomesh.io/cloud-endpoint-hash: "12101461380361539607"
    flomesh.io/cloud-service-inherited-from: httpbin
    flomesh.io/mesh-service-sync: eureka
    flomesh.io/mesh-service-sync-managed-by: af8360a6-cbb8-4c42-8e80-6cbc1c0c5230
  creationTimestamp: "2025-03-09T05:53:09Z"
  labels:
    fsm-connector-cloud-sourced-service: "true"
  name: httpbin-eureka
  namespace: tenant-liaoning
  resourceVersion: "78706"
  uid: 236751c9-153f-4743-b52a-7925649d1d4c
spec:
  externalName: httpbin-eureka.liaoning.tenant
  ports:
  - appProtocol: http
    name: http14001
    port: 14001
    protocol: TCP
    targetPort: 14001
  selector:
    fsm-connector-cloud-service: httpbin-eureka
  sessionAffinity: None
  type: ExternalName
status:
  loadBalancer: {}
```

### 7.5 配置 ExternalName 解析记录

```bash
kubectl get dnsmodifier -n fsm-system egress-dns-resolve-db -o json | jq '.spec.zones["tenant-liaoning"].domains += [{"answer": {"rdata": "11.11.0.111"},"name": "httpbin-eureka.liaoning.tenant"}]' | kubectl apply -f -

kubectl get dnsmodifier -n fsm-system ingress-dns-resolve-db -o json | jq '.spec.zones["tenant-liaoning"].domains += [{"answer": {"rdata": "11.11.0.111"},"name": "httpbin-eureka.liaoning.tenant"}]' | kubectl apply -f -

kubectl get dnsmodifier -n fsm-system egress-dns-resolve-db -o json | jq '.spec.zones["tenant-liaoning"].domains += [{"answer": {"rdata": "11.11.0.111"},"name": "httpbin-eureka.tenant-liaoning.svc.cluster.local"}]' | kubectl apply -f -

kubectl get dnsmodifier -n fsm-system ingress-dns-resolve-db -o json | jq '.spec.zones["tenant-liaoning"].domains += [{"answer": {"rdata": "11.11.0.111"},"name": "httpbin-eureka.tenant-liaoning.svc.cluster.local"}]' | kubectl apply -f -
```

### 7.6 httpbin-eureka 调用效果

多次执行:

```bash
echo $(kubectl exec "$(kubectl get pod -n tenant-liaoning  -l app=curl -o jsonpath='{.items..metadata.name}')" -n tenant-liaoning -- curl -s httpbin-eureka.liaoning.tenant:14001)

echo $(kubectl exec "$(kubectl get pod -n tenant-liaoning  -l app=curl -o jsonpath='{.items..metadata.name}')" -n tenant-liaoning -- curl -s httpbin-eureka:14001)
```

返回结果如下:

```bash
demo1.httpbin.eureka.smartdns.local
```

## 8 导入租户 Nacos 服务

### 8.1 部署 nacos connector

```
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
```

### 8.2 查看 nacos 上的服务

```bash
kubectl get nacosconnector -n tenant-liaoning nacos-to-tenant-liaoning -o jsonpath='{.status.catalogServices}' | jq
```

返回结果如下:

```json
[
  {
    "service": "httpbin"
  }
]
```

### 8.3 导入 nacos 上的服务

```bash
kubectl get nacosconnector -n tenant-liaoning nacos-to-tenant-liaoning -o json | jq '.spec.syncToK8S.conversionStrategy.serviceConversions += [{"service": "httpbin", "convertName": "httpbin-nacos", "externalName": "httpbin-nacos.liaoning.tenant"}]' | kubectl apply -f -
```

### 8.4 查看已经导入的服务

```bash
kubectl get service httpbin-nacos -n tenant-liaoning -o yaml
```

返回结果如下:

```yaml
apiVersion: v1
kind: Service
metadata:
  annotations:
    flomesh.io/cloud-endpoint-addr: eyJwb3J0cyI6eyIxNDAwMSI6Imh0dHAifSwiZW5kcG9pbnRzIjp7IjIyLjIyLjAuMjIxIjp7InBvcnRzIjp7IjE0MDAxIjoiaHR0cCJ9LCJhZGRyZXNzIjoiMjIuMjIuMC4yMjEiLCJuYXRpdmUiOnsidmlhR2F0ZXdheU1vZGUiOiJmb3J3YXJkIn0sImxvY2FsIjp7fX0sIjIyLjIyLjAuMjIyIjp7InBvcnRzIjp7IjE0MDAxIjoiaHR0cCJ9LCJhZGRyZXNzIjoiMjIuMjIuMC4yMjIiLCJuYXRpdmUiOnsidmlhR2F0ZXdheU1vZGUiOiJmb3J3YXJkIn0sImxvY2FsIjp7fX19fQ==
    flomesh.io/cloud-endpoint-hash: "16689463773998680651"
    flomesh.io/cloud-service-inherited-from: httpbin
    flomesh.io/mesh-service-sync: nacos
    flomesh.io/mesh-service-sync-managed-by: 63de936c-4372-4863-84b6-dcd3ff032be1
  creationTimestamp: "2025-03-09T06:01:11Z"
  labels:
    fsm-connector-cloud-sourced-service: "true"
  name: httpbin-nacos
  namespace: tenant-liaoning
  resourceVersion: "79872"
  uid: bccc2187-5f4d-4ce5-aedc-050f4cf118bc
spec:
  externalName: httpbin-nacos.liaoning.tenant
  ports:
  - appProtocol: http
    name: http14001
    port: 14001
    protocol: TCP
    targetPort: 14001
  selector:
    fsm-connector-cloud-service: httpbin-nacos
  sessionAffinity: None
  type: ExternalName
status:
  loadBalancer: {}
```

### 8.5 配置 ExternalName 解析记录

```bash
kubectl get dnsmodifier -n fsm-system egress-dns-resolve-db -o json | jq '.spec.zones["tenant-liaoning"].domains += [{"answer": {"rdata": "22.22.0.221"},"name": "httpbin-nacos.liaoning.tenant"}]' | kubectl apply -f -

kubectl get dnsmodifier -n fsm-system ingress-dns-resolve-db -o json | jq '.spec.zones["tenant-liaoning"].domains += [{"answer": {"rdata": "22.22.0.221"},"name": "httpbin-nacos.liaoning.tenant"}]' | kubectl apply -f -

kubectl get dnsmodifier -n fsm-system egress-dns-resolve-db -o json | jq '.spec.zones["tenant-liaoning"].domains += [{"answer": {"rdata": "22.22.0.221"},"name": "httpbin-nacos.tenant-liaoning.svc.cluster.local"}]' | kubectl apply -f -

kubectl get dnsmodifier -n fsm-system ingress-dns-resolve-db -o json | jq '.spec.zones["tenant-liaoning"].domains += [{"answer": {"rdata": "22.22.0.221"},"name": "httpbin-nacos.tenant-liaoning.svc.cluster.local"}]' | kubectl apply -f -
```

### 8.6 httpbin-nacos 调用效果

多次执行:

```bash
echo $(kubectl exec "$(kubectl get pod -n tenant-liaoning  -l app=curl -o jsonpath='{.items..metadata.name}')" -n tenant-liaoning -- curl -s httpbin-nacos.liaoning.tenant:14001)

echo $(kubectl exec "$(kubectl get pod -n tenant-liaoning  -l app=curl -o jsonpath='{.items..metadata.name}')" -n tenant-liaoning -- curl -s httpbin-nacos:14001)
```

返回结果如下:

```bash
demo1.httpbin.nacos.smartdns.local
```

## 9 SmartDNS 业务测试

### 9.1 tenant-liaoning/httpbin 配置 EIP

```bash
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
```

### 9.2 tenant-liaoning/httpbin-eureka 配置 EIP

```bash
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
```

### 9.3 tenant-liaoning/httpbin-nacos 配置 EIP

```bash
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
```

### 9.4 业务功能测试

#### 9.4.1 K8S集群内测试

##### 9.4.1.1  解析 google.com 域名

执行:

```bash
kubectl exec "$(kubectl get pod -n tenant-liaoning -l app=curl -o jsonpath='{.items..metadata.name}')" -n tenant-liaoning -- nslookup google.com
```

返回结果如下:

```bash
Server:		10.96.0.10
Address:	10.96.0.10:53

Non-authoritative answer:
Name:	google.com
Address: 22.22.22.22

Non-authoritative answer:
Name:	google.com
Address: 22.22.22.22
```

##### 9.4.1.2 K8S集群内经 EIP 访问跨网段 Eureka 微服务

###### 9.4.1.2.1 eureka/httpbin 调用效果

多次执行:

```bash
echo $(kubectl exec "$(kubectl get pod -n tenant-liaoning  -l app=curl -o jsonpath='{.items..metadata.name}')" -n tenant-liaoning -- curl -s 192.168.127.187:14001)
```

返回结果如下:

```bash
demo1.httpbin.eureka.smartdns.local
demo2.httpbin.eureka.smartdns.local
```

##### 9.4.1.3 K8S集群内经 EIP 访问跨网段 Nacos 微服务

###### 9.4.1.3.1 nacos/httpbin 调用效果

多次执行:

```bash
echo $(kubectl exec "$(kubectl get pod -n tenant-liaoning -l app=curl -o jsonpath='{.items..metadata.name}')" -n tenant-liaoning -- curl -s 192.168.127.188:14001)
```

返回结果如下:

```bash
demo1.httpbin.nacos.smartdns.local
demo2.httpbin.nacos.smartdns.local
```

#### 9.4.2 K8S集群外测试

##### 9.4.2.1 K8S集群外经 EIP 访问 K8S 内微服务

###### 9.4.2.1.1 demo/httpbin 调用效果

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

##### 9.4.2.2 K8S集群外经 EIP 访问跨网段 Eureka 微服务

###### 9.4.2.2.1 eureka/httpbin 调用效果

多次执行:

```bash
curl -s 192.168.127.187:14001
```

返回结果如下:

```bash
demo1.httpbin.eureka.smartdns.local
demo2.httpbin.eureka.smartdns.local
```

##### 9.4.2.3 K8S集群外经 EIP 访问跨网段 Nacos 微服务

###### 9.4.2.3.1 nacos/httpbin 调用效果

多次执行:

```bash
curl -s 192.168.127.188:14001
```

返回结果如下:

```bash
demo1.httpbin.nacos.smartdns.local
demo2.httpbin.nacos.smartdns.local
```

