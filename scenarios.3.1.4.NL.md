# 场景 Nebula gRPC 单集群微服务融合测试

## 1 部署 C1 集群

```bash
clusters="C1" make k3d-up
```

## 2 部署服务

### 2.1 C1集群

```bash
kubecm switch k3d-C1
```

### 2.2 部署 FSM Mesh

```bash
fsm_cluster_name=C1 sidecar=NodeLevel make deploy-fsm
```

### 2.3 部署 fgw

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
      name: igrs-grpc
      allowedRoutes:
        namespaces:
          from: All
    - protocol: HTTP
      port: 15001
      name: mesh-grpc
      allowedRoutes:
        namespaces:
          from: All
EOF

kubectl apply -f - <<EOF
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: ListenerFilter
metadata:
  name: node-sidecar-accesslog
  namespace: fsm-system
spec:
  type: AccessLog
  aspect: Route
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: node-sidecar
      port: 15001
EOF
```

### 2.4 部署 zookeeper 服务

```bash
make zk-deploy
#ZOOKEEPER_PORT_FORWARD=12181:2181 ZOOWEBUI_PORT_FORWARD=18081:8081 make zk-port-forward

export c1_zookeeper_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_zookeeper_cluster_ip $c1_zookeeper_cluster_ip

export c1_zookeeper_external_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_zookeeper_external_ip $c1_zookeeper_external_ip

export c1_zookeeper_pod_ip="$(kubectl get pod -n default --selector app=zookeeper -o jsonpath='{.items[0].status.podIP}')"
echo c1_zookeeper_pod_ip $c1_zookeeper_pod_ip
```

### 2.5 配置 zookeeper 服务访问控制策略

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

### 2.6 创建 derive-zookeeper namespace

```bash
kubectl create namespace derive-zookeeper
fsm namespace add derive-zookeeper
kubectl patch namespace derive-zookeeper -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"zookeeper"}}}'  --type=merge
```

### 2.7 部署 zookeeper connector(c1-zookeeper-to-c1-derive-zookeeper)

```
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-zookeeper-to-c1-derive-zookeeper
spec:
  httpAddr: $c1_zookeeper_cluster_ip:2181
  deriveNamespace: derive-zookeeper
  basePath: /Application/grpc
  category: providers
  adaptor: nebula
  asInternalServices: true
  syncToK8S:
    enable: true
  syncFromK8S:
    enable: false
EOF
```

### 2.8 部署 fgw connector

```bash
kubectl apply  -f - <<EOF
kind: GatewayConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: node-sidecar
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

### 2.9 部署 Nebula gRPC 微服务

```bash
WITH_MESH=true fsm_cluster_name=c1 replicas=2 make deploy-zookeeper-nebula-grcp-server
WITH_MESH=true fsm_cluster_name=c1 replicas=1 make deploy-zookeeper-nebula-grcp-client
```

## 3 服务调用效果

### 3.1 切换集群

```bash
kubecm switch k3d-C1
export c1_client_pod_name="$(kubectl get pod -n client --selector app=nebula-grpc-client -o jsonpath='{.items[0].metadata.name}')"
echo c1_client_pod_name $c1_client_pod_name
```

### 3.2 确认服务调用效果

**多次执行:**

```bash
kubectl logs -n client $c1_client_pod_name -c client -f
```

**正确返回结果类似于:**

```bash
success: true
message: "Miss Alice, well done.(\346\210\221\347\210\261\345\244\217\345\244\251)"
no: 200
salary: 7200.0
total: 1733633489387
```

## 4 卸载 C1 集群

```bash
clusters="C1" make k3d-reset
```
