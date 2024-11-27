# 场景 Consul 跨集群微服务融合HA测试

## 测试目的

- [ ] **跨集群云上服务的 HA**
  - **derive local 空间下无云上服务实例对 FailOver的影响**
  - **无原生服务实例对 FailOver的影响**

- [ ] **原生应用同云上服务HA**
  - **derive local 空间下无云上服务实例对 FailOver的影响**
  - **无原生服务实例对 FailOver的影响**

- [ ] **固定服务端口**
  - **需要进一步探讨对云上服务实例被网格纳管的情形**

## 1 部署 C1 C2 C3 三个集群

```bash
export clusters="C1 C2 C3"
make k3d-up
```

## 2 部署服务

### 2.1 C1集群

```bash
kubecm switch k3d-C1
```

#### 2.1.1 部署 FSM Mesh

```bash
fsm_cluster_name=C1 make deploy-fsm
```

#### 2.1.2 启用按请求负载均衡策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"http1PerRequestLoadBalancing":true}}}' --type=merge
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"gatewayAPI":{"http1PerRequestLoadBalancing":true}}}' --type=merge
```

#### 2.1.2 部署 Consul 微服务

```bash
make consul-deploy

PORT_FORWARD="8501:8500" make consul-port-forward &

export c1_consul_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=consul -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_consul_cluster_ip $c1_consul_cluster_ip

export c1_consul_external_ip="$(kubectl get svc -n default --field-selector metadata.name=consul -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_consul_external_ip $c1_consul_external_ip

export c1_consul_pod_ip="$(kubectl get pod -n default --selector app=consul -o jsonpath='{.items[0].status.podIP}')"
echo c1_consul_pod_ip $c1_consul_pod_ip

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

WITH_MESH=true fsm_cluster_name=c1 replicas=1 make deploy-consul-httpbin
```

### 2.2 C2集群

```bash
kubecm switch k3d-C2
```

#### 2.2.1 部署 FSM Mesh

```bash
fsm_cluster_name=C2 make deploy-fsm
```

#### 2.2.2 启用按请求负载均衡策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"http1PerRequestLoadBalancing":true}}}' --type=merge
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"gatewayAPI":{"http1PerRequestLoadBalancing":true}}}' --type=merge
```

#### 2.2.3 部署 Consul 微服务

```bash
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

WITH_MESH=true fsm_cluster_name=c2 replicas=1 make deploy-consul-httpbin
```

### 2.3 C3集群

```bash
kubecm switch k3d-C3
```

#### 2.3.1 部署 FSM Mesh

```bash
fsm_cluster_name=C3 make deploy-fsm
```

#### 2.3.2 启用按请求负载均衡策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"http1PerRequestLoadBalancing":true}}}' --type=merge
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"gatewayAPI":{"http1PerRequestLoadBalancing":true}}}' --type=merge
```

#### 2.3.3 部署 Consul 微服务

```bash
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
kind: FilterConfig
metadata:
 name:  proxytag-fc
spec:
  config: |
    proxyTag:
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
     port: 10090
 definitionRef:
   group: extension.gateway.flomesh.io
   kind: FilterDefinition
   name: proxytag-def
 configRef:
   group: extension.gateway.flomesh.io
   kind: FilterConfig
   name: proxytag-fc
EOF
```

#### 3.1.2 部署 fgw

```bash
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

sleep 3

kubectl wait --all --for=condition=ready pod -n "$fsm_namespace" -l app=fsm-gateway --timeout=180s

until kubectl get service/fsm-gateway-fsm-system-k8s-c1-fgw-tcp -n $fsm_namespace --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

kubectl patch AccessControl -n fsm-policy global --type=json -p='[{"op": "add", "path": "/spec/sources/-", "value": {"kind":"Service","namespace":"fsm-system","name":"fsm-gateway-fsm-system-k8s-c1-fgw-tcp"}}]'

export c1_fgw_cluster_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c1-fgw-tcp -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_fgw_cluster_ip $c1_fgw_cluster_ip

export c1_fgw_external_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c1-fgw-tcp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_fgw_external_ip $c1_fgw_external_ip

export c1_fgw_pod_ip="$(kubectl get pod -n $fsm_namespace --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo c1_fgw_pod_ip $c1_fgw_pod_ip
```

#### 3.1.3 导入本集群 consul 微服务

##### 3.1.3.1 创建 derive-local namespace

```bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"consul"}}}'  --type=merge
```

##### 3.1.3.2 部署 consul connector(c1-consul-to-c1-derive-local)

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

#### 3.1.4 部署 consul connector(c1-k8s-to-c3-consul)

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

#### 3.1.5 部署 fgw connector

```bash
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
kind: FilterConfig
metadata:
 name:  proxytag-fc
spec:
  config: |
    proxyTag:
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
     port: 10090
 definitionRef:
   group: extension.gateway.flomesh.io
   kind: FilterDefinition
   name: proxytag-def
 configRef:
   group: extension.gateway.flomesh.io
   kind: FilterConfig
   name: proxytag-fc
EOF
```

#### 3.2.2 部署 fgw

```bash
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

sleep 3

kubectl wait --all --for=condition=ready pod -n "$fsm_namespace" -l app=fsm-gateway --timeout=180s

until kubectl get service/fsm-gateway-fsm-system-k8s-c2-fgw-tcp -n $fsm_namespace --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

kubectl patch AccessControl -n fsm-policy global --type=json -p='[{"op": "add", "path": "/spec/sources/-", "value": {"kind":"Service","namespace":"fsm-system","name":"fsm-gateway-fsm-system-k8s-c2-fgw-tcp"}}]'

export c2_fgw_cluster_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c2-fgw-tcp -o jsonpath='{.items[0].spec.clusterIP}')"
echo c2_fgw_cluster_ip $c2_fgw_cluster_ip

export c2_fgw_external_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c2-fgw-tcp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c2_fgw_external_ip $c2_fgw_external_ip

export c2_fgw_pod_ip="$(kubectl get pod -n $fsm_namespace --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo c2_fgw_pod_ip $c2_fgw_pod_ip
```

#### 3.2.3 导入本集群 consul 微服务

##### 3.2.3.1 创建 derive-local namespace

```bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"consul"}}}'  --type=merge
```

##### 3.2.3.2 部署 consul connector(c2-consul-to-c2-derive-local)

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

#### 3.2.4 部署 consul connector(c2-k8s-to-c3-consul)

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

#### 3.2.5 部署 fgw connector

```bash
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
kind: FilterConfig
metadata:
 name:  proxytag-fc
spec:
  config: |
    proxyTag:
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
     port: 10090
 definitionRef:
   group: extension.gateway.flomesh.io
   kind: FilterDefinition
   name: proxytag-def
 configRef:
   group: extension.gateway.flomesh.io
   kind: FilterConfig
   name: proxytag-fc
EOF
```

#### 3.3.2 部署 fgw

```bash
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

sleep 3

kubectl wait --all --for=condition=ready pod -n "$fsm_namespace" -l app=fsm-gateway --timeout=180s

until kubectl get service/fsm-gateway-fsm-system-k8s-c3-fgw-tcp -n $fsm_namespace --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

kubectl patch AccessControl -n fsm-policy global --type=json -p='[{"op": "add", "path": "/spec/sources/-", "value": {"kind":"Service","namespace":"fsm-system","name":"fsm-gateway-fsm-system-k8s-c3-fgw-tcp"}}]'

export c3_fgw_cluster_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c3-fgw-tcp -o jsonpath='{.items[0].spec.clusterIP}')"
echo c3_fgw_cluster_ip $c3_fgw_cluster_ip

export c3_fgw_external_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-c3-fgw-tcp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c3_fgw_external_ip $c3_fgw_external_ip

export c3_fgw_pod_ip="$(kubectl get pod -n $fsm_namespace --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo c3_fgw_pod_ip $c3_fgw_pod_ip
```

#### 3.3.3 导入本集群 consul 微服务

##### 3.3.3.1 创建 derive-local namespace

```bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"consul"}}}'  --type=merge
```

##### 3.3.3.2 部署 consul connector(c3-consul-to-c3-derive-local)

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

#### 3.3.4 导入其他集群 consul 微服务

##### 3.3.4.1 创建 derive-other namespace

```bash
kubectl create namespace derive-other
fsm namespace add derive-other
kubectl patch namespace derive-other -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"consul"}}}'  --type=merge

kubectl patch namespace derive-other -p '{"metadata":{"annotations":{"flomesh.io/cloud-service-attached-to":"derive-local"}}}'  --type=merge
```

##### 3.3.4.2 部署 consul connector(c3-consul-to-c3-derive-other)

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

#### 3.3.5 部署 fgw connector

```bash
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
      - derive-local
      - derive-other
EOF
```

#### 3.3.6 设置云上服务 HA 策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"connector":{"lb":{"type":"FailOver","masterNamespace":"derive-local","slaveNamespaces":["derive-other"]}}}}' --type=merge
```

#### 3.3.7 设置原生服务 HA 策略

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

## 4 优化策略

### 4.1 C1集群

#### 4.1.1 启用服务仅 IP访问模式

```bash
kubecm switch k3d-C1
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"serviceAccessMode":"ip"}}}' --type=merge
```

#### 4.1.2 禁用 DNS 代理

```bash
kubecm switch k3d-C1
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"sidecar":{"localDNSProxy":{"enable": false}}}}' --type=merge
```

### 4.2 C2集群

#### 4.2.1 启用服务仅 IP访问模式

```bash
kubecm switch k3d-C2
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"serviceAccessMode":"ip"}}}' --type=merge
```

#### 4.2.2 禁用 DNS 代理

```bash
kubecm switch k3d-C2
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"sidecar":{"localDNSProxy":{"enable": false}}}}' --type=merge
```

### 4.3 C3集群

#### 4.3.1 禁用 DNS 代理

```bash
kubecm switch k3d-C3
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"sidecar":{"localDNSProxy":{"enable": false}}}}' --type=merge
```

#### 4.3.2 启用服务仅 IP访问模式

```bash
kubecm switch k3d-C3
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"serviceAccessMode":"ip"}}}' --type=merge
```

#### 4.3.3 启用服务仅 服务名访问模式

```bash
kubecm switch k3d-C3
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"serviceAccessMode":"domain"}}}' --type=merge
```

#### 4.3.4 关闭服务名TrustDomain 后缀

```bash
kubecm switch k3d-C3
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"serviceAccessNames":{"withTrustDomain":false}}}}' --type=merge
```

#### 4.3.5 禁用不带端口号服务名

```bash
kubecm switch k3d-C3
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"serviceAccessNames":{"mustWithServicePort":true}}}}' --type=merge
```

#### 4.3.6 禁用带 Namespace 的云服务名

```bash
kubecm switch k3d-C3
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"serviceAccessNames":{"cloud":{"withNamespace":false}}}}}' --type=merge
```

#### 4.3.7 启用服务去重模式

```bash
kubecm switch k3d-C3
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableSidecarPrettyConfig":false}}}' --type=merge
```

#### 4.3.8 启用fgw日志插件

```bash
kubectl apply -f - <<EOF
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: ListenerFilter
metadata:
  name: k8s-c3-fgw-accesslog
  namespace: fsm-system
spec:
  type: AccessLog
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: k8s-c3-fgw
      port: 10090
EOF
```

#### 4.3.9 启用fgw ProxyTag插件

```bash
kubectl apply -f - <<EOF
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: FilterDefinition
metadata:
 name: proxytag-def
spec:
  scope: Listener
  protocol: tcp
  type: ProxyTag
  script: |
    export default function (config) {
      var proxyTag = (config.proxyTag?.dstHostHeader || 'proxy-tag').toLowerCase()
      var origHost = (config.proxyTag?.srcHostHeader || 'orig-host').toLowerCase()

      return pipeline(\$=>\$
        .demuxHTTP().to(\$=>\$
          .handleMessageStart(
            msg => {
              var headers = msg.head.headers
              var tag = headers[proxyTag]
              if (tag) {
                headers[origHost] = headers.host
                headers.host = tag
              } else if (headers['fgw-target-service']) {
                headers[proxyTag] = headers['fgw-target-service']
              } else {
                headers[proxyTag] = headers.host
              }
            }
          )
          .pipeNext()
        )
      )
    }
EOF

kubectl apply -n fsm-system -f - <<EOF
---
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: FilterConfig
metadata:
 name:  proxytag-fc
spec:
  config: |
    proxyTag:
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
     port: 10090
 definitionRef:
   group: extension.gateway.flomesh.io
   kind: FilterDefinition
   name: proxytag-def
 configRef:
   group: extension.gateway.flomesh.io
   kind: FilterConfig
   name: proxytag-fc
EOF
```

## 5 集群调度策略

### 5.1 切换集群

```bash
kubecm switch k3d-C3
export c3_curl_pod_name="$(kubectl get pod -n curl --selector app=curl -o jsonpath='{.items[0].metadata.name}')"
echo c3_curl_pod_name $c3_curl_pod_name
```

### 5.2 查看集群调度策略

```bash
kubectl get meshconfigs -n fsm-system fsm-mesh-config -o jsonpath='{.spec.connector.lb.type}'
```

### 5.3 FailOver

#### 5.3.1 设置集群调度策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"connector":{"lb":{"type":"FailOver","masterNamespace":"derive-local","slaveNamespaces":["derive-other"]}}}}' --type=merge
```

#### 5.3.2 确认服务调用效果

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

### 5.4 ActiveActive

#### 5.4.1 设置集群调度策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"connector":{"lb":{"type":"ActiveActive"}}}}' --type=merge
```

#### 5.4.2 确认服务调用效果

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

## 6 卸载 C1 C2 C3 三个集群

```bash
export clusters="C1 C2 C3"
make k3d-reset
```

## 7 常用指令

```bash
make deploy-native-httpbin-fault

kubectl scale deployment -n demo httpbin --replicas=1
kubectl scale deployment -n httpbin c3-httpbin --replicas=1

kubectl rollout restart deployment -n fsm-system fsm-connector-consul-c3-consul-to-c3-derive-local
 
export derive_local_pod_name="$(kubectl get pod -n fsm-system --selector app=fsm-connector-consul-c3-consul-to-c3-derive-local -o jsonpath='{.items[0].metadata.name}')"
kubectl logs -n fsm-system $derive_local_pod_name -f
```

