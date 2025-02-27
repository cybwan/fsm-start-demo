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
fsm_cluster_name=C1 sidecar=PodLevel make deploy-fsm
```

### 2.3 启用按请求负载均衡策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"http1PerRequestLoadBalancing":true}}}' --type=merge
```

### 2.4 部署 Zookeeper 微服务

```bash
make zk-deploy
#ZOOKEEPER_PORT_FORWARD=12181:2181 ZOOWEBUI_PORT_FORWARD=18081:8081 make zk-port-forward

export c1_zookeeper_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_zookeeper_cluster_ip $c1_zookeeper_cluster_ip

export c1_zookeeper_external_ip="$(kubectl get svc -n default --field-selector metadata.name=zookeeper -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_zookeeper_external_ip $c1_zookeeper_external_ip

export c1_zookeeper_pod_ip="$(kubectl get pod -n default --selector app=zookeeper -o jsonpath='{.items[0].status.podIP}')"
echo c1_zookeeper_pod_ip $c1_zookeeper_pod_ip

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
    name: zookeeper
EOF

WITH_MESH=true fsm_cluster_name=c1 replicas=2 make deploy-zookeeper-nebula-grcp-server
WITH_MESH=true fsm_cluster_name=c1 replicas=1 make deploy-zookeeper-nebula-grcp-client
```

## 3 微服务融合

### 3.1 C1 集群

```bash
kubecm switch k3d-C1
```

### 3.2 导入本集群 zookeeper 微服务

#### 3.2.1 创建 derive-local namespace

```bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"zookeeper"}}}'  --type=merge
```

#### 3.2.2 部署 zookeeper connector(c1-zookeeper-to-c1-derive-local)

```
kubectl apply  -f - <<EOF
kind: ZookeeperConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-zookeeper-to-c1-derive-local
spec:
  httpAddr: $c1_zookeeper_cluster_ip:2181
  deriveNamespace: derive-local
  basePath: /Application/grpc
  category: providers
  adaptor: nebula
  asInternalServices: true
  syncToK8S:
    enable: true
    filterIpRanges:
      - 10.101.0.0/16
    withGateway: 
      enable: false
  syncFromK8S:
    enable: false
EOF
```

## 4 服务调用效果

### 4.1 切换集群

```bash
kubecm switch k3d-C1
export c1_client_pod_name="$(kubectl get pod -n client --selector app=nebula-grpc-client -o jsonpath='{.items[0].metadata.name}')"
echo c1_client_pod_name $c1_client_pod_name
```

### 4.2 确认服务调用效果

**多次执行:**

```bash
kubectl logs -n client $c1_client_pod_name -c client -f
```

**正确返回结果类似于:

```bash
success: true
message: "Miss Alice, well done.(\346\210\221\347\210\261\345\244\217\345\244\251)"
no: 200
salary: 7200.0
total: 1733633489387
```

## 5 卸载 C1 集群

```bash
clusters="C1" make k3d-reset
```
