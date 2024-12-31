# 场景 Nebula gRPC 多集群微服务融合测试

## 1 部署 K8S 三个集群

```bash
clusters="C1 C2 C3" make k3d-up
```

## 2 部署服务

### 2.1 C1集群

```bash
kubecm switch k3d-C1
```

#### 2.1.1 部署网格服务

```bash
fsm_cluster_name=C1 sidecar=NodeLevel make deploy-fsm
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

#### 2.1.3 部署 zookeeper 服务

```bash
make zk-deploy
#ZOOKEEPER_PORT_FORWARD=12181:2181 ZOOWEBUI_PORT_FORWARD=18081:8081 make zk-port-forward &

export c1_zookeeper_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_zookeeper_cluster_ip $c1_zookeeper_cluster_ip

export c1_zookeeper_external_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_zookeeper_external_ip $c1_zookeeper_external_ip

export c1_zookeeper_pod_ip="$(kubectl get pod -n default --selector app=zookeeper -o jsonpath='{.items[0].status.podIP}')"
echo c1_zookeeper_pod_ip $c1_zookeeper_pod_ip
```

#### 2.1.4 配置 zookeeper 服务访问控制策略

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
    name: zookeeper
EOF
```

#### 2.1.5 部署 nebula grpc 微服务

```bash
WITH_MESH=true fsm_cluster_name=c1 make deploy-zookeeper-nebula-grcp-server
```

### 2.2 C2集群

```bash
kubecm switch k3d-C2
```

#### 2.2.1 部署网格服务

```bash
fsm_cluster_name=C2 sidecar=NodeLevel make deploy-fsm
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

#### 2.2.3 部署 zookeeper 服务

```bash
make zk-deploy
#ZOOKEEPER_PORT_FORWARD=22181:2181 ZOOWEBUI_PORT_FORWARD=18081:8081 make zk-port-forward &

export c2_zookeeper_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].spec.clusterIP}')"
echo c2_zookeeper_cluster_ip $c2_zookeeper_cluster_ip

export c2_zookeeper_external_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c2_zookeeper_external_ip $c2_zookeeper_external_ip

export c2_zookeeper_pod_ip="$(kubectl get pod -n default --selector app=zookeeper -o jsonpath='{.items[0].status.podIP}')"
echo c2_zookeeper_pod_ip $c2_zookeeper_pod_ip
```

#### 2.2.4 配置 zookeeper 服务访问控制策略

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
    name: zookeeper
EOF
```

#### 2.2.5 部署 nebula grpc 微服务

```bash
WITH_MESH=true fsm_cluster_name=c2 make deploy-zookeeper-nebula-grcp-server
```

### 2.3 C3集群

```bash
kubecm switch k3d-C3
```

#### 2.3.1 部署网格服务

```bash
fsm_cluster_name=C3 sidecar=NodeLevel make deploy-fsm
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

#### 2.3.3 部署 zookeeper 服务

```bash
make zk-deploy
#ZOOKEEPER_PORT_FORWARD=32181:2181 ZOOWEBUI_PORT_FORWARD=18081:8081 make zk-port-forward &

export c3_zookeeper_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].spec.clusterIP}')"
echo c3_zookeeper_cluster_ip $c3_zookeeper_cluster_ip

export c3_zookeeper_external_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c3_zookeeper_external_ip $c3_zookeeper_external_ip

export c3_zookeeper_pod_ip="$(kubectl get pod -n default --selector app=zookeeper -o jsonpath='{.items[0].status.podIP}')"
echo c3_zookeeper_pod_ip $c3_zookeeper_pod_ip
```

#### 2.3.4 配置 zookeeper 服务访问控制策略

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
    name: zookeeper
EOF
```

#### 2.3.5 部署 nebula grpc 微服务

```bash
WITH_MESH=true fsm_cluster_name=c3 replicas=0 make deploy-zookeeper-nebula-grcp-server
WITH_MESH=true fsm_cluster_name=c3 make deploy-zookeeper-nebula-grcp-client
```

## 3 微服务融合

### 3.1 C1 集群

```bash
kubecm switch k3d-C1
```

#### 3.1.1 部署 fgw connector

```bash
kubectl apply  -f - <<EOF
kind: GatewayConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-fgw
spec:
  gatewayName: node-sidecar
  ingress:
    ipSelector: ExternalIP
    grpcPort: 10080
  egress:
    ipSelector: ClusterIP
    grpcPort: 15001
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - derive-zookeeper
EOF
```

#### 3.1.2 创建 derive-zookeeper namespace

```bash
kubectl create namespace derive-zookeeper
fsm namespace add derive-zookeeper
kubectl patch namespace derive-zookeeper -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"zookeeper"}}}'  --type=merge
```

#### 3.1.3 部署 zookeeper connector(c1-zk-to-c1-derive-zk)

```
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-zk-to-c1-derive-zk
spec:
  httpAddr: $c1_zookeeper_cluster_ip:2181
  deriveNamespace: derive-zookeeper
  basePath: /Application/grpc
  category: providers
  adaptor: nebula
  asInternalServices: true
  syncToK8S:
    enable: true
    withGateway: 
      enable: true
  syncFromK8S:
    enable: false
EOF
```

#### 3.1.4 部署 zookeeper connector(c1-k8s-to-c2-zk)

**c1 k8s微服务同步到c2 zookeeper**

```
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-k8s-to-c2-zk
spec:
  httpAddr: $c2_zookeeper_external_ip:2181
  deriveNamespace: none
  basePath: /Application/grpc
  category: providers
  adaptor: nebula
  syncToK8S:
    enable: false
  syncFromK8S:
    enable: true
    withGateway: 
      enable: true
    allowK8sNamespaces:
      - derive-zookeeper
EOF
```

### 3.2 C2 集群

```bash
kubecm switch k3d-C2
```

#### 3.2.1 部署 fgw connector

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
    grpcPort: 10080
  egress:
    ipSelector: ClusterIP
    grpcPort: 15001
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - derive-zookeeper
EOF
```

#### 3.2.2 创建 derive-zookeeper namespace

```bash
kubectl create namespace derive-zookeeper
fsm namespace add derive-zookeeper
kubectl patch namespace derive-zookeeper -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"zookeeper"}}}'  --type=merge
```

#### 3.2.3 部署 zookeeper connector(c2-zk-to-c2-derive-zk)

```
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c2-zk-to-c2-derive-zk
spec:
  httpAddr: $c2_zookeeper_cluster_ip:2181
  deriveNamespace: derive-zookeeper
  basePath: /Application/grpc
  category: providers
  adaptor: nebula
  asInternalServices: true
  syncToK8S:
    enable: true
    withGateway: 
      enable: true
  syncFromK8S:
    enable: false
EOF
```

#### 3.2.4 部署 zookeeper connector(c2-k8s-to-c3-zk)

**c2 k8s微服务同步到c3 zookeeper**

```
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c2-k8s-to-c3-zk
spec:
  httpAddr: $c3_zookeeper_external_ip:2181
  deriveNamespace: none
  basePath: /Application/grpc
  category: providers
  adaptor: nebula
  syncToK8S:
    enable: false
  syncFromK8S:
    enable: true
    withGateway: 
      enable: true
    allowK8sNamespaces:
      - derive-zookeeper
EOF
```

### 3.3 C3 集群

```bash
kubecm switch k3d-C3
```

#### 3.3.1 部署 fgw connector

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
    grpcPort: 10080
  egress:
    ipSelector: ClusterIP
    grpcPort: 15001
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - derive-zookeeper
EOF
```

#### 3.3.2 创建 derive-zookeeper namespace

```bash
kubectl create namespace derive-zookeeper
fsm namespace add derive-zookeeper
kubectl patch namespace derive-zookeeper -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"zookeeper"}}}'  --type=merge
```

#### 3.3.3 部署 zookeeper connector(c3-zk-to-c3-derive-zk)

```
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c3-zk-to-c3-derive-zk
spec:
  httpAddr: $c3_zookeeper_cluster_ip:2181
  deriveNamespace: derive-zookeeper
  basePath: /Application/grpc
  category: providers
  adaptor: nebula
  asInternalServices: true
  syncToK8S:
    enable: true
    withGateway: 
      enable: true
  syncFromK8S:
    enable: false
EOF
```

## 4 确认服务调用效果

测试指令:

```bash
export c3_client_pod_name="$(kubectl get pod -n client --selector app=nebula-grpc-client -o jsonpath='{.items[0].metadata.name}')"
echo c3_client_pod_name $c3_client_pod_name

kubectl logs -n client $c3_client_pod_name -c client -f
```

确认运行效果,返回:

```bash
success: true
message: "Miss Alice, well done.(\346\210\221\347\210\261\345\244\217\345\244\251)"
no: 200
salary: 7200.0
total: 1733633489387
```

## 5 卸载 K8S 三个集群

```bash
clusters="C1 C2 C3" make k3d-reset
```
