# 场景 Global Zookeeper 多集群微服务融合测试

## 1 部署 K8S 三个集群

```bash
clusters="C0 C1 C2 C3" make k3d-up
```

## 2 部署服务

### 2.1 C0 集群

```bash
kubecm switch k3d-C0
```

#### 2.1.1 部署 zookeeper 服务

```bash
make zk-deploy

sleep 3

kubectl wait --all --for=condition=ready pod -l app=zookeeper --timeout=180s

until kubectl get service/zookeeper --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

export global_zookeeper_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].spec.clusterIP}')"
echo global_zookeeper_cluster_ip $global_zookeeper_cluster_ip

export global_zookeeper_external_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo global_zookeeper_external_ip $global_zookeeper_external_ip

export global_zookeeper_pod_ip="$(kubectl get pod -n default --selector app=zookeeper -o jsonpath='{.items[0].status.podIP}')"
echo global_zookeeper_pod_ip $global_zookeeper_pod_ip

ZOOKEEPER_PORT_FORWARD=12181:2181 ZOOWEBUI_PORT_FORWARD=18081:8081 make zk-port-forward
```

#### 2.1.2 创建服务目录

```bash
kubectl exec -it $(kubectl get pod -n default --selector app=zookeeper -o jsonpath='{.items[0].metadata.name}') -n default -c zookeeper -- zkCli.sh create /k8s k8s
```

### 2.2 C1集群

```bash
kubecm switch k3d-C1
```

#### 2.2.1 部署网格服务

```bash
fsm_cluster_name=C1 sidecar=PodLevel make deploy-fsm
```

#### 2.2.2 部署 fgw

```bash
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
```

#### 2.2.3 设置访问控制策略

```bash
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
```

#### 2.2.4 部署 fgw connector

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
      - demo
EOF
```

#### 2.2.5 部署 k8s native 微服务

```bash
WITH_MESH=true fsm_cluster_name=c1 make deploy-hostname-httpbin
```

### 2.3 C2集群

```bash
kubecm switch k3d-C2
```

#### 2.3.1 部署网格服务

```bash
fsm_cluster_name=C2 sidecar=PodLevel make deploy-fsm
```

#### 2.3.2 部署 fgw

```bash
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
    name: fsm-gateway-fsm-system-k8s-c2-fgw-tcp
EOF
```

#### 2.3.3 设置访问控制策略

```bash
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
    name: fsm-gateway-fsm-system-k8s-c2-fgw-tcp
EOF
```

#### 2.3.4 部署 fgw connector

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
      - demo
EOF
```

#### 2.3.5 部署 k8s native 微服务

```bash
WITH_MESH=false fsm_cluster_name=c1 make deploy-hostname-httpbin
```

### 2.4 C3集群

```bash
kubecm switch k3d-C3
```

#### 2.4.1 部署网格服务

```bash
fsm_cluster_name=C3 sidecar=PodLevel make deploy-fsm
```

#### 2.4.2 部署 fgw

```bash
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
    name: fsm-gateway-fsm-system-k8s-c3-fgw-tcp
EOF
```

#### 2.4.3 设置访问控制策略

```bash
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
    name: fsm-gateway-fsm-system-k8s-c3-fgw-tcp
EOF
```

#### 2.4.3 部署 fgw connector

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
      - derive-other
EOF
```

#### 2.4.4 部署 k8s native 微服务

```bash
WITH_MESH=false fsm_cluster_name=c3 make deploy-native-curl
```

## 3 微服务融合

### 3.1 C1 集群

```bash
kubecm switch k3d-C1
```

#### 3.1.1 部署 zookeeper connector(c1-k8s-to-global-zk)

**c1 k8s微服务同步到global zookeeper**

```
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-k8s-to-global-zk
spec:
  httpAddr: $global_zookeeper_external_ip:2181
  deriveNamespace: none
  basePath: /k8s
  category: providers
  adaptor: k8s
  syncToK8S:
    enable: false
  syncFromK8S:
    enable: true
    withGateway: 
      enable: true
    allowK8sNamespaces:
      - demo
EOF
```

### 3.2 C2 集群

```bash
kubecm switch k3d-C2
```

#### 3.2.1 部署 zookeeper connector(c2-k8s-to-global-zk)

**c2 k8s微服务同步到global zookeeper**

```
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c2-k8s-to-global-zk
spec:
  httpAddr: $global_zookeeper_external_ip:2181
  deriveNamespace: none
  basePath: /k8s
  category: providers
  adaptor: k8s
  syncToK8S:
    enable: false
  syncFromK8S:
    enable: true
    withGateway: 
      enable: true
    allowK8sNamespaces:
      - demo
EOF
```

### 3.3 C3 集群

```bash
kubecm switch k3d-C3
```

#### 3.3.3 导入其他集群 zookeeper 微服务

##### 3.3.3.1 创建 derive-other namespace

```bash
kubectl create namespace derive-other
fsm namespace add derive-other
kubectl patch namespace derive-other -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"zookeeper"}}}'  --type=merge
```

##### 3.3.3.2 部署 zookeeper connector(global-zk-to-c3-derive-other)

```
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: global-zk-to-c3-derive-other
spec:
  httpAddr: $global_zookeeper_external_ip:2181
  deriveNamespace: derive-other
  asInternalServices: false
  basePath: /k8s
  category: providers
  adaptor: k8s
  syncToK8S:
    enable: true
    excludeIpRanges:
      - 10.104.1.0/24
    withGateway: 
      enable: true
  syncFromK8S:
    enable: false
EOF
```

## 4 确认服务调用效果

测试指令:

```bash
export c3_curl_pod_name="$(kubectl get pod -n demo --selector app=curl -o jsonpath='{.items[0].metadata.name}')"
echo c3_curl_pod_name $c3_curl_pod_name

kubectl exec -n demo $c3_curl_pod_name -c curl -- curl -s httpbin:80 -I
```

确认运行效果,返回:

```bash
hi, I am httpbin from host: httpbin-849db69c94-qzkk8 at node: k3d-c1-server-0 by pipy!
hi, I am httpbin from host: httpbin-849db69c94-s4w2c at node: k3d-c2-server-0 by pipy!
```

## 5 卸载 K8S 三个集群

```bash
clusters="C0 C1 C2 C3" make k3d-reset
```

## 6 便捷工具

https://www.urldecoder.org/
