# 场景 SmartDNS & Calico & vxlan 业务测试

## 1 部署 K8S 集群

```bash
clusters="C1" make k3d-calico-up
```

## 2 部署 SmartDNS 服务

```bash
kubecm switch k3d-C1

#export CTR_REGISTRY=192.168.226.1:5000/flomesh
#export CTR_TAG=latest

fsm_cluster_name=C1 sidecar=NodeLevel k8s=true mesh=true e4lb=true e4lb_cni=calicoVxlan make deploy-smartdns

# 无须 injector, 删除 injector
kubectl delete deployments.apps -n fsm-system fsm-injector
```

## 3 部署 SmartDNS FGW 服务

### 3.1 部署 FGW

```bash
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
          kubernetes.io/hostname: k3d-c1-server-0
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

kubectl patch meshconfig fsm-mesh-config -n fsm-system -p '{"spec":{"sidecar":{"xnetDNSProxy":{"enable":true,"upstreams":[{"name":"fsm-gateway-fsm-system-smart-dns-fgw-udp","namespace":"fsm-system","port":10053}]}}}}'  --type=merge
```

### 3.2 配置 INGRESS 方向 DNS filter

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

### 3.3 配置 EGRESS 方向 DNS filter

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

### 3.4 SmartDNS UDPRoute 授权

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

## 4 部署 Eureka 集群

```bash
docker run -d --network fsm --ip 172.22.0.230 --rm --name smartdns-eureka -p 8761:8761 -t flomesh/samples-discovery-server:latest

#等待 eureka 服务启动
sleep 30s

docker run -d --hostname demo1.httpbin.eureka.smartdns.local --network fsm --ip 172.22.0.231 -e EUREKA_SERVICE_URL=http://172.22.0.230:8761/eureka/ --rm --name smartdns-eureka-httpbin-demo-1 -t cybwan/smartdns-eureka-httpbin-demo:latest java -Dotel.traces.exporter=none -Dotel.metrics.exporter=none -Dotel.propagators=tracecontext,baggage,b3multi -jar httpbin-eureka.jar

docker run -d --hostname demo2.httpbin.eureka.smartdns.local --network fsm --ip 172.22.0.232 -e EUREKA_SERVICE_URL=http://172.22.0.230:8761/eureka/ --rm --name smartdns-eureka-httpbin-demo-2 -t cybwan/smartdns-eureka-httpbin-demo:latest java -Dotel.traces.exporter=none -Dotel.metrics.exporter=none -Dotel.propagators=tracecontext,baggage,b3multi -jar httpbin-eureka.jar
```

## 5 部署 Nacos 集群

```bash
docker run -d --network fsm --ip 172.22.0.220 --rm -e MODE=standalone --name smartdns-nacos -p 8848:8848 -t nacos/nacos-server:v2.3.0-slim

#等待 nacos 服务启动
sleep 20s

docker run -d --hostname demo1.httpbin.nacos.smartdns.local --network fsm --ip 172.22.0.221 -e NACOS_SERVICE_URL=172.22.0.220:8848 --rm --name smartdns-nacos-httpbin-demo-1 -t cybwan/smartdns-nacos-httpbin-demo:latest java -Dotel.traces.exporter=none -Dotel.metrics.exporter=none -Dotel.propagators=tracecontext,baggage,b3multi -jar httpbin-nacos.jar

docker run -d --hostname demo2.httpbin.nacos.smartdns.local --network fsm --ip 172.22.0.222 -e NACOS_SERVICE_URL=172.22.0.220:8848 --rm --name smartdns-nacos-httpbin-demo-2 -t cybwan/smartdns-nacos-httpbin-demo:latest java -Dotel.traces.exporter=none -Dotel.metrics.exporter=none -Dotel.propagators=tracecontext,baggage,b3multi -jar httpbin-nacos.jar
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
  httpAddr: http://172.22.0.230:8761/eureka
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
kubectl get eurekaconnector -n tenant-liaoning eureka-to-tenant-liaoning -o json | jq '.spec.syncToK8S.conversionStrategy.serviceConversions += [{"service": "httpbin", "convertName": "httpbin-eureka"}]' | kubectl apply -f -
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
    flomesh.io/cloud-endpoint-addr: eyJwb3J0cyI6eyIxNDAwMSI6Imh0dHAifSwiZW5kcG9pbnRzIjp7IjE3Mi4yMi4wLjIzMSI6eyJwb3J0cyI6eyIxNDAwMSI6Imh0dHAifSwiYWRkcmVzcyI6IjE3Mi4yMi4wLjIzMSIsIm5hdGl2ZSI6eyJ2aWFHYXRld2F5TW9kZSI6ImZvcndhcmQifSwibG9jYWwiOnt9fSwiMTcyLjIyLjAuMjMyIjp7InBvcnRzIjp7IjE0MDAxIjoiaHR0cCJ9LCJhZGRyZXNzIjoiMTcyLjIyLjAuMjMyIiwibmF0aXZlIjp7InZpYUdhdGV3YXlNb2RlIjoiZm9yd2FyZCJ9LCJsb2NhbCI6e319fX0=
    flomesh.io/cloud-endpoint-hash: "11815722161519085205"
    flomesh.io/cloud-service-inherited-from: httpbin
    flomesh.io/mesh-service-sync: eureka
    flomesh.io/mesh-service-sync-managed-by: 56519441-bc41-4eed-910e-4fe2efcc97f7
  creationTimestamp: "2025-03-21T01:36:07Z"
  labels:
    fsm-connector-cloud-sourced-service: "true"
  name: httpbin-eureka
  namespace: tenant-liaoning
  resourceVersion: "1942"
  uid: 0a94fb38-26e6-4501-b992-2a5f0e5ce021
spec:
  clusterIP: None
  clusterIPs:
  - None
  ipFamilies:
  - IPv4
  ipFamilyPolicy: SingleStack
  ports:
  - appProtocol: http
    name: http14001
    port: 14001
    protocol: TCP
    targetPort: 14001
  sessionAffinity: None
  type: ClusterIP
status:
  loadBalancer: {}
```

### 7.5 httpbin-eureka 调用效果

多次执行:

```bash
echo $(kubectl exec "$(kubectl get pod -n tenant-liaoning  -l app=curl -o jsonpath='{.items..metadata.name}')" -n tenant-liaoning -- curl -s httpbin-eureka:14001)
```

返回结果如下:

```bash
demo1.httpbin.eureka.smartdns.local
demo2.httpbin.eureka.smartdns.local
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
  httpAddr: 172.22.0.220:8848
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
kubectl get nacosconnector -n tenant-liaoning nacos-to-tenant-liaoning -o json | jq '.spec.syncToK8S.conversionStrategy.serviceConversions += [{"service": "httpbin", "convertName": "httpbin-nacos"}]' | kubectl apply -f -
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
    flomesh.io/cloud-endpoint-addr: eyJwb3J0cyI6eyIxNDAwMSI6Imh0dHAifSwiZW5kcG9pbnRzIjp7IjE3Mi4yMi4wLjIyMSI6eyJwb3J0cyI6eyIxNDAwMSI6Imh0dHAifSwiYWRkcmVzcyI6IjE3Mi4yMi4wLjIyMSIsIm5hdGl2ZSI6eyJ2aWFHYXRld2F5TW9kZSI6ImZvcndhcmQifSwibG9jYWwiOnt9fSwiMTcyLjIyLjAuMjIyIjp7InBvcnRzIjp7IjE0MDAxIjoiaHR0cCJ9LCJhZGRyZXNzIjoiMTcyLjIyLjAuMjIyIiwibmF0aXZlIjp7InZpYUdhdGV3YXlNb2RlIjoiZm9yd2FyZCJ9LCJsb2NhbCI6e319fX0=
    flomesh.io/cloud-endpoint-hash: "8809065757199745393"
    flomesh.io/cloud-service-inherited-from: httpbin
    flomesh.io/mesh-service-sync: nacos
    flomesh.io/mesh-service-sync-managed-by: edce33cb-c4ca-437c-98ef-82b5d571dc26
  creationTimestamp: "2025-03-21T01:39:01Z"
  labels:
    fsm-connector-cloud-sourced-service: "true"
  name: httpbin-nacos
  namespace: tenant-liaoning
  resourceVersion: "2178"
  uid: 2b22da26-ac49-424a-bd00-6cc8ea2980fe
spec:
  clusterIP: None
  clusterIPs:
  - None
  ipFamilies:
  - IPv4
  ipFamilyPolicy: SingleStack
  ports:
  - appProtocol: http
    name: http14001
    port: 14001
    protocol: TCP
    targetPort: 14001
  sessionAffinity: None
  type: ClusterIP
status:
  loadBalancer: {}
```

### 8.5 httpbin-nacos 调用效果

多次执行:

```bash
echo $(kubectl exec "$(kubectl get pod -n tenant-liaoning  -l app=curl -o jsonpath='{.items..metadata.name}')" -n tenant-liaoning -- curl -s httpbin-nacos:14001)
```

返回结果如下:

```bash
demo1.httpbin.nacos.smartdns.local
demo2.httpbin.nacos.smartdns.local
```

## 9 SmartDNS 业务测试

### 9.1 EIP 业务测试

#### 9.1.1 配置 EIP

##### 9.1.1.1 tenant-liaoning/httpbin 配置 EIP

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
  eips:
  - 172.22.0.186
  nodes:
  - k3d-c1-server-0
EOF
```

##### 9.1.1.2 tenant-liaoning/httpbin-eureka 配置 EIP

```bash
kubectl apply -n tenant-liaoning -f - <<EOF
kind: EIPAdvertisement
apiVersion: xnetwork.flomesh.io/v1alpha1
metadata:
  name: httpbin-eureka
spec:
  service: 
    name: httpbin-eureka
  eips:
  - 172.22.0.187
  nodes:
  - k3d-c1-server-0
EOF
```

##### 9.1.1.3 tenant-liaoning/httpbin-nacos 配置 EIP

```bash
kubectl apply -n tenant-liaoning -f - <<EOF
kind: EIPAdvertisement
apiVersion: xnetwork.flomesh.io/v1alpha1
metadata:
  name: httpbin-nacos
spec:
  service: 
    name: httpbin-nacos
  eips:
  - 172.22.0.188
  nodes:
  - k3d-c1-server-0
EOF
```

#### 9.1.2 功能测试

##### 9.1.2.1 K8S集群内测试

###### 9.1.2.1.1 K8S集群内经 EIP 访问跨网段 Eureka 微服务

多次执行:

```bash
echo $(kubectl exec "$(kubectl get pod -n tenant-liaoning  -l app=curl -o jsonpath='{.items..metadata.name}')" -n tenant-liaoning -- curl -s 172.22.0.187:14001)
```

返回结果如下:

```bash
demo1.httpbin.eureka.smartdns.local
demo2.httpbin.eureka.smartdns.local
```

###### 9.1.2.1.2 K8S集群内经 EIP 访问跨网段 Nacos 微服务

多次执行:

```bash
echo $(kubectl exec "$(kubectl get pod -n tenant-liaoning -l app=curl -o jsonpath='{.items..metadata.name}')" -n tenant-liaoning -- curl -s 172.22.0.188:14001)
```

返回结果如下:

```bash
demo1.httpbin.nacos.smartdns.local
demo2.httpbin.nacos.smartdns.local
```

##### 9.1.2.2 K8S集群外测试

###### 9.1.2.2.1 部署集群外部模拟客户端

```bash
docker run -d --dns 8.8.8.8 --privileged --network fsm --rm --name smartdns-client -t cybwan/curl:latest sleep 1h
```

###### 9.1.2.2.2 K8S集群外经 EIP 访问 K8S 内微服务

多次执行:

```bash
docker exec smartdns-client /usr/bin/curl -s 172.22.0.186:80
```

返回结果如下:

```bash
hi, I am httpbin from host: httpbin-84dc4dcffd-hqbzr at node: worker1 by pipy!
hi, I am httpbin from host: httpbin-84dc4dcffd-dnsq4 at node: worker2 by pipy!
```

调用效果是分别从两个服务实例返回.

###### 9.1.2.2.3 K8S集群外经 EIP 访问跨网段 Eureka 微服务

多次执行:

```bash
docker exec smartdns-client /usr/bin/curl -s 172.22.0.187:14001
```

返回结果如下:

```bash
demo1.httpbin.eureka.smartdns.local
demo2.httpbin.eureka.smartdns.local
```

###### 9.1.2.2.4 K8S集群外经 EIP 访问跨网段 Nacos 微服务

多次执行:

```bash
docker exec smartdns-client /usr/bin/curl -s 172.22.0.188:14001
```

返回结果如下:

```bash
demo1.httpbin.nacos.smartdns.local
demo2.httpbin.nacos.smartdns.local
```

### 9.2 DNS 业务测试

#### 9.2.1 配置 DNS Resolve DB

##### 9.2.1.1 配置全局 DNS Resolve DB

```bash
kubectl get dnsmodifier -n fsm-system egress-dns-resolve-db -o json | jq '.spec.zones["global"].domains += [{"answer": {"rdata": "6.6.6.6"},"name": "google.com"}]' | kubectl apply -f -
```

#### 9.2.2 功能测试

##### 9.2.2.1 集群内 DNS 测试

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
Address: 6.6.6.6

Non-authoritative answer:
Name:	google.com
Address: 6.6.6.6
```

## 10 卸载 K8S 集群

```bash
clusters="C1" make k3d-reset

docker stop smartdns-eureka-httpbin-demo-1
docker stop smartdns-eureka-httpbin-demo-2
docker stop smartdns-eureka

docker stop smartdns-nacos-httpbin-demo-1
docker stop smartdns-nacos-httpbin-demo-2
docker stop smartdns-nacos

docker stop smartdns-client
```
