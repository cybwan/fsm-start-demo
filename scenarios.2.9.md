# 场景 Consul 多集群微服务高可用测试

## 测试目的

- [ ] **跨集群云上服务的 HA**
  - **derive local 空间下无云上服务实例对 FailOver的影响**
  - **无原生服务实例对 FailOver的影响**

- [ ] **原生应用同云上服务HA**
  - **derive local 空间下无云上服务实例对 FailOver的影响**
  - **无原生服务实例对 FailOver的影响**

- [ ] **固定服务端口**
  - **需要进一步探讨对云上服务实例被网格纳管的情形**

## 1 部署 K8S 三个集群

```bash
export clusters="C1 C2 C3"
make k3d-up
```

## 2 部署服务

### 2.1 C1集群

```bash
kubecm switch k3d-C1
```

#### 2.1.1 部署网格服务

```bash
fsm_cluster_name=C1 make deploy-fsm
```

#### 2.1.2 部署 fgw

```bash
kubectl apply -n fsm-system -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: node-sidecar
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
      port: 15001
      name: mesh-http
      allowedRoutes:
        namespaces:
          from: All
EOF

sleep 3

kubectl wait --all --for=condition=ready pod -n fsm-system -l app=fsm-gateway --timeout=180s

until kubectl get service/fsm-gateway-fsm-system-node-sidecar-tcp -n fsm-system --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

export c1_fgw_cluster_ip="$(kubectl get svc -n fsm-system --field-selector metadata.name=fsm-gateway-fsm-system-node-sidecar-tcp -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_fgw_cluster_ip $c1_fgw_cluster_ip

export c1_fgw_external_ip="$(kubectl get svc -n fsm-system --field-selector metadata.name=fsm-gateway-fsm-system-node-sidecar-tcp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_fgw_external_ip $c1_fgw_external_ip

export c1_fgw_pod_ip="$(kubectl get pod -n fsm-system --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo c1_fgw_pod_ip $c1_fgw_pod_ip
```

#### 2.1.3 部署 Consul 服务

```bash
make consul-deploy

#PORT_FORWARD="8501:8500" make consul-port-forward &

export c1_consul_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=consul -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_consul_cluster_ip $c1_consul_cluster_ip

export c1_consul_external_ip="$(kubectl get svc -n default --field-selector metadata.name=consul -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_consul_external_ip $c1_consul_external_ip

export c1_consul_pod_ip="$(kubectl get pod -n default --selector app=consul -o jsonpath='{.items[0].status.podIP}')"
echo c1_consul_pod_ip $c1_consul_pod_ip
```

#### 2.1.4 配置 Consul 服务访问控制策略

```bash
kubectl create namespace fsm-policy
fsm namespace add fsm-policy

kubectl apply -f - <<EOF
kind: AccessControl
apiVersion: xnetwork.flomesh.io/v1alpha1
metadata:
  name: global
  namespace: fsm-policy
spec:
  services:
  - namespace: default
    name: consul
    withEndpointIPs: true
EOF
```

#### 2.1.5 部署 Consul 微服务

```bash
WITH_MESH=true fsm_cluster_name=c1 replicas=1 make deploy-consul-httpbin
```

### 2.2 C2集群

```bash
kubecm switch k3d-C2
```

#### 2.2.1 部署网格服务

```bash
fsm_cluster_name=C2 make deploy-fsm
```

#### 2.2.2 部署 fgw

```bash
kubectl apply -n fsm-system -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: node-sidecar
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
      port: 15001
      name: mesh-http
      allowedRoutes:
        namespaces:
          from: All
EOF

sleep 3

kubectl wait --all --for=condition=ready pod -n fsm-system -l app=fsm-gateway --timeout=180s

until kubectl get service/fsm-gateway-fsm-system-node-sidecar-tcp -n fsm-system --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

export c2_fgw_cluster_ip="$(kubectl get svc -n fsm-system --field-selector metadata.name=fsm-gateway-fsm-system-node-sidecar-tcp -o jsonpath='{.items[0].spec.clusterIP}')"
echo c2_fgw_cluster_ip $c2_fgw_cluster_ip

export c2_fgw_external_ip="$(kubectl get svc -n fsm-system --field-selector metadata.name=fsm-gateway-fsm-system-node-sidecar-tcp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c2_fgw_external_ip $c2_fgw_external_ip

export c2_fgw_pod_ip="$(kubectl get pod -n fsm-system --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo c2_fgw_pod_ip $c2_fgw_pod_ip
```

#### 2.2.3 部署 Consul 服务

```bash
make consul-deploy

#PORT_FORWARD="8502:8500" make consul-port-forward &

export c2_consul_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=consul -o jsonpath='{.items[0].spec.clusterIP}')"
echo c2_consul_cluster_ip $c2_consul_cluster_ip

export c2_consul_external_ip="$(kubectl get svc -n default --field-selector metadata.name=consul -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c2_consul_external_ip $c2_consul_external_ip

export c2_consul_pod_ip="$(kubectl get pod -n default --selector app=consul -o jsonpath='{.items[0].status.podIP}')"
echo c2_consul_pod_ip $c2_consul_pod_ip
```

#### 2.2.4 配置 Consul 服务访问控制策略

```bash
kubectl create namespace fsm-policy
fsm namespace add fsm-policy

kubectl apply -f - <<EOF
kind: AccessControl
apiVersion: xnetwork.flomesh.io/v1alpha1
metadata:
  name: global
  namespace: fsm-policy
spec:
  services:
  - namespace: default
    name: consul
    withEndpointIPs: true
EOF
```

#### 2.2.5 部署 Consul 微服务

```bash
WITH_MESH=true fsm_cluster_name=c2 replicas=1 make deploy-consul-httpbin
```

### 2.3 C3集群

```bash
kubecm switch k3d-C3
```

#### 2.3.1 部署网格服务

```bash
fsm_cluster_name=C3 make deploy-fsm
```

#### 2.3.2 部署 fgw

```bash
kubectl apply -n fsm-system -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: node-sidecar
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
      port: 15001
      name: mesh-http
      allowedRoutes:
        namespaces:
          from: All
EOF

sleep 3

kubectl wait --all --for=condition=ready pod -n fsm-system -l app=fsm-gateway --timeout=180s

until kubectl get service/fsm-gateway-fsm-system-node-sidecar-tcp -n fsm-system --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

export c3_fgw_cluster_ip="$(kubectl get svc -n fsm-system --field-selector metadata.name=fsm-gateway-fsm-system-node-sidecar-tcp -o jsonpath='{.items[0].spec.clusterIP}')"
echo c3_fgw_cluster_ip $c3_fgw_cluster_ip

export c3_fgw_external_ip="$(kubectl get svc -n fsm-system --field-selector metadata.name=fsm-gateway-fsm-system-node-sidecar-tcp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c3_fgw_external_ip $c3_fgw_external_ip

export c3_fgw_pod_ip="$(kubectl get pod -n fsm-system --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo c3_fgw_pod_ip $c3_fgw_pod_ip
```

#### 2.3.3 部署 Consul 服务

```bash
make consul-deploy

#PORT_FORWARD="8503:8500" make consul-port-forward &

export c3_consul_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=consul -o jsonpath='{.items[0].spec.clusterIP}')"
echo c3_consul_cluster_ip $c3_consul_cluster_ip

export c3_consul_external_ip="$(kubectl get svc -n default --field-selector metadata.name=consul -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c3_consul_external_ip $c3_consul_external_ip

export c3_consul_pod_ip="$(kubectl get pod -n default --selector app=consul -o jsonpath='{.items[0].status.podIP}')"
echo c3_consul_pod_ip $c3_consul_pod_ip
```

#### 2.3.4 配置 Consul 服务访问控制策略

```bash
kubectl create namespace fsm-policy
fsm namespace add fsm-policy

kubectl apply -f - <<EOF
kind: AccessControl
apiVersion: xnetwork.flomesh.io/v1alpha1
metadata:
  name: global
  namespace: fsm-policy
spec:
  services:
  - namespace: default
    name: consul
    withEndpointIPs: true
EOF
```

#### 2.3.5 部署 Consul 微服务

```bash
WITH_MESH=false fsm_cluster_name=c3 replicas=0 make deploy-consul-httpbin
WITH_MESH=true fsm_cluster_name=c3 replicas=1 make deploy-native-httpbin
```

## 3 微服务融合

### 3.1 C1 集群

```bash
kubecm switch k3d-C1
```

#### 3.1.1 启用 fgw ProxyTag插件

```bash
kubectl apply -n fsm-system -f - <<EOF
---
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: ProxyTag
metadata:
  name:  proxytag-fc
spec:
  dstHostHeader: "fgw-forwarded-service"
  srcHostHeader: "host"
---
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: ListenerFilter
metadata:
 name: proxytag
spec:
 type: ProxyTag
 targetRefs:
   - group: gateway.networking.k8s.io
     kind: Gateway
     name: k8s-c3-fgw
     port: 15001
 configRef:
   group: extension.gateway.flomesh.io
   kind: FilterConfig
   name: proxytag-fc
EOF
```

#### 3.1.2 导入本集群 consul 微服务

##### 3.1.2.1 创建 derive-local namespace

```bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"consul"}}}'  --type=merge
```

##### 3.1.2.2 部署 consul connector(c1-consul-to-c1-derive-local)

```
kubectl apply  -f - <<EOF
kind: ConsulConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-consul-to-c1-derive-local
spec:
  httpAddr: $c1_consul_cluster_ip:8500
  deriveNamespace: derive-local
  asInternalServices: true
  syncToK8S:
    enable: true
    filterIpRanges:
      - 10.101.1.0/24
    withGateway: 
      enable: true
  syncFromK8S:
    enable: false
EOF
```

#### 3.1.3 部署 consul connector(c1-k8s-to-c3-consul)

**c1 k8s微服务同步到c3 consul**

```
kubectl apply  -f - <<EOF
kind: ConsulConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-k8s-to-c3-consul
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
      - derive-local
EOF
```

#### 3.1.4 部署 fgw connector

```bash
kubectl apply  -f - <<EOF
kind: GatewayConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-fgw
spec:
  gatewayName: node-sideca
  ingress:
    ipSelector: ExternalIP
    httpPort: 10080
  egress:
    ipSelector: ClusterIP
    httpPort: 15001
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - derive-local
EOF
```

### 3.2 C2 集群

```bash
kubecm switch k3d-C2
```

#### 3.2.1 启用 fgw ProxyTag插件

```bash
kubectl apply -n fsm-system -f - <<EOF
---
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: ProxyTag
metadata:
  name:  proxytag-fc
spec:
  dstHostHeader: "fgw-forwarded-service"
  srcHostHeader: "host"
---
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: ListenerFilter
metadata:
 name: proxytag
spec:
 type: ProxyTag
 targetRefs:
   - group: gateway.networking.k8s.io
     kind: Gateway
     name: k8s-c3-fgw
     port: 15001
 configRef:
   group: extension.gateway.flomesh.io
   kind: FilterConfig
   name: proxytag-fc
EOF
```

#### 3.2.2 导入本集群 consul 微服务

##### 3.2.2.1 创建 derive-local namespace

```bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"consul"}}}'  --type=merge
```

##### 3.2.2.2 部署 consul connector(c2-consul-to-c2-derive-local)

```
kubectl apply  -f - <<EOF
kind: ConsulConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-consul-to-c2-derive-local
spec:
  httpAddr: $c2_consul_cluster_ip:8500
  deriveNamespace: derive-local
  asInternalServices: true
  syncToK8S:
    enable: true
    filterIpRanges:
      - 10.102.1.0/24
    withGateway: 
      enable: true
  syncFromK8S:
    enable: false
EOF
```

#### 3.2.3 部署 consul connector(c2-k8s-to-c3-consul)

**c2 k8s微服务同步到c3 consul**

```
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
      - derive-local
EOF
```

#### 3.2.4 部署 fgw connector

```bash
kubectl apply  -f - <<EOF
kind: GatewayConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c2-fgw
spec:
  gatewayName: node-sidecar
  ingress:
    ipSelector: ExternalIP
    httpPort: 10080
  egress:
    ipSelector: ClusterIP
    httpPort: 15001
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - derive-local
EOF
```

### 3.3 C3 集群

```bash
kubecm switch k3d-C3
```

#### 3.3.1 启用 fgw ProxyTag插件

```bash
kubectl apply -n fsm-system -f - <<EOF
---
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: ProxyTag
metadata:
  name:  proxytag-fc
spec:
  dstHostHeader: "fgw-forwarded-service"
  srcHostHeader: "host"
---
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: ListenerFilter
metadata:
 name: proxytag
spec:
 type: ProxyTag
 targetRefs:
   - group: gateway.networking.k8s.io
     kind: Gateway
     name: k8s-c3-fgw
     port: 15001
 configRef:
   group: extension.gateway.flomesh.io
   kind: FilterConfig
   name: proxytag-fc
EOF
```

#### 3.3.2 导入本集群 consul 微服务

##### 3.3.2.1 创建 derive-local namespace

```bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"consul"}}}'  --type=merge
```

##### 3.3.2.2 部署 consul connector(c3-consul-to-c3-derive-local)

```
kubectl apply  -f - <<EOF
kind: ConsulConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c3-consul-to-c3-derive-local
spec:
  httpAddr: $c3_consul_cluster_ip:8500
  deriveNamespace: derive-local
  asInternalServices: true
  syncToK8S:
    enable: true
    filterIpRanges:
      - 10.103.1.0/24
    withGateway: 
      enable: true
    fixedHttpServicePort: 80
  syncFromK8S:
    enable: false
EOF
```

#### 3.3.3 导入其他集群 consul 微服务

##### 3.3.3.1 创建 derive-other namespace

```bash
kubectl create namespace derive-other
fsm namespace add derive-other
kubectl patch namespace derive-other -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"consul"}}}'  --type=merge

kubectl patch namespace derive-other -p '{"metadata":{"annotations":{"flomesh.io/cloud-service-attached-to":"derive-local"}}}'  --type=merge
```

##### 3.3.3.2 部署 consul connector(c3-consul-to-c3-derive-other)

```
kubectl apply  -f - <<EOF
kind: ConsulConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c3-consul-to-c3-derive-other
spec:
  httpAddr: $c3_consul_cluster_ip:8500
  deriveNamespace: derive-other
  asInternalServices: false
  syncToK8S:
    enable: true
    excludeIpRanges:
      - 10.103.1.0/24
    withGateway: 
      enable: true
    fixedHttpServicePort: 80
    generateInternalServiceHealthCheck: false
  syncFromK8S:
    enable: false
EOF
```

#### 3.3.4 部署 fgw connector

```bash
kubectl apply  -f - <<EOF
kind: GatewayConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c3-fgw
spec:
  gatewayName: node-sidecar
  ingress:
    ipSelector: ExternalIP
    httpPort: 10080
  egress:
    ipSelector: ClusterIP
    httpPort: 15001
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - derive-local
      - derive-other
EOF
```

#### 3.3.5 设置云上服务 HA 策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"connector":{"lb":{"type":"FailOver","masterNamespace":"derive-local","slaveNamespaces":["derive-other"]}}}}' --type=merge
```

#### 3.3.6 设置原生服务 HA 策略

```bash
cat <<EOF | kubectl apply -n derive-local -f -
apiVersion: split.smi-spec.io/v1alpha4
kind: TrafficSplit
metadata:
  name: httpbin-split-v4
spec:
  service: derive-local/httpbin
  backends:
  - service: demo/httpbin
    weight: 100
  - service: derive-local/httpbin
    weight: 0
EOF

cat <<EOF | kubectl apply -n demo -f -
apiVersion: split.smi-spec.io/v1alpha4
kind: TrafficSplit
metadata:
  name: httpbin-split-v4
spec:
  service: demo/httpbin
  backends:
  - service: demo/httpbin
    weight: 100
  - service: derive-local/httpbin
    weight: 0
EOF
```

## 4 集群调度策略

### 4.1 切换集群

```bash
kubecm switch k3d-C3
export c3_curl_pod_name="$(kubectl get pod -n curl --selector app=curl -o jsonpath='{.items[0].metadata.name}')"
echo c3_curl_pod_name $c3_curl_pod_name
```

### 4.2 查看集群调度策略

```bash
kubectl get meshconfigs -n fsm-system fsm-mesh-config -o jsonpath='{.spec.connector.lb.type}'
```

### 4.3 FailOver

#### 4.3.1 设置集群调度策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"connector":{"lb":{"type":"FailOver","masterNamespace":"derive-local","slaveNamespaces":["derive-other"]}}}}' --type=merge
```

#### 4.3.2 确认服务调用效果

**多次执行:**

```bash
kubectl exec -n curl $c3_curl_pod_name -c curl -- curl -s 127.0.0.1:14001
```

**正确返回结果类似于:**

```bash
c3-httpbin-5dd47d8645-ddhj5
c3-httpbin-5dd47d8645-ddhj5
c3-httpbin-5dd47d8645-ddhj5
```

### 4.4 ActiveActive

#### 4.4.1 设置集群调度策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"connector":{"lb":{"type":"ActiveActive"}}}}' --type=merge
```

#### 4.4.2 确认服务调用效果

**多次执行:**

```bash
kubectl exec -n curl $c3_curl_pod_name -c curl -- curl -s 127.0.0.1:14001
```

**正确返回结果类似于:**

```bash
c3-httpbin-5dd47d8645-ddhj5
c1-httpbin-5dd47d8645-mm2bg
c2-httpbin-5dd47d8645-lsdh8
```

## 5 卸载 K8S 三个集群

```bash
export clusters="C1 C2 C3"
make k3d-reset

WITH_MESH=true fsm_cluster_name=c3 replicas=1 make deploy-consul-curl
```
