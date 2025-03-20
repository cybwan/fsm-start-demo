# 场景 Nacos 单集群微服务融合测试

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

### 2.4 部署 Nacos 微服务

```bash
make nacos-deploy
#PORT_FORWARD="18848:8848" make nacos-port-forward &

export c1_nacos_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=nacos -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_nacos_cluster_ip $c1_nacos_cluster_ip

export c1_nacos_external_ip="$(kubectl get svc -n default --field-selector metadata.name=nacos -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_nacos_external_ip $c1_nacos_external_ip

export c1_nacos_pod_ip="$(kubectl get pod -n default --selector app=nacos -o jsonpath='{.items[0].status.podIP}')"
echo c1_nacos_pod_ip $c1_nacos_pod_ip

kubectl create namespace fsm-policy
fsm namespace add fsm-policy

kubectl apply -n fsm-policy -f - <<EOF
kind: AccessControl
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: global
spec:
  sources:
  - kind: Service
    namespace: default
    name: nacos
EOF

WITH_MESH=true fsm_cluster_name=c1 replicas=2 make deploy-nacos-httpbin
WITH_MESH=true fsm_cluster_name=c1 replicas=1 make deploy-nacos-curl
```

## 3 微服务融合

### 3.1 C1 集群

```bash
kubecm switch k3d-C1
```

### 3.2 导入本集群 nacos 微服务

#### 3.2.1 创建 derive-local namespace

```bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"nacos"}}}'  --type=merge
```

#### 3.2.2 部署 nacos connector(c1-nacos-to-c1-derive-local)

```bash
kubectl apply -n "$fsm_namespace"  -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-nacos-to-c1-derive-local
spec:
  httpAddr: $c1_nacos_external_ip:8848
  deriveNamespace: derive-local
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
export c1_curl_pod_name="$(kubectl get pod -n curl --selector app=curl -o jsonpath='{.items[0].metadata.name}')"
echo c1_curl_pod_name $c1_curl_pod_name
```

### 4.2 确认服务调用效果

**多次执行:**

```bash
kubectl exec -n curl $c1_curl_pod_name -c curl -- curl -s httpbin:14001
kubectl exec -n curl $c1_curl_pod_name -c curl -- curl -s httpbin:14001
```

**正确返回结果类似于:**

```bash
c1-httpbin-8497f8477b-lbrbv
c1-httpbin-8497f8477b-vhrfq
```

## 5 卸载 C1 集群

```bash
clusters="C1" make k3d-reset
```
