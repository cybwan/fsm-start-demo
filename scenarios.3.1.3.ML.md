# 场景 Nacos 单集群微服务融合测试

## 1 部署 C1 集群

```bash
clusters="C1" make k3d-up
```

## 2 部署服务

### 2.1 部署 FSM Mesh

```bash
fsm_cluster_name=C1 sidecar=PodLevel make deploy-fsm

# 无须 injector, 删除 injector
kubectl delete deployments.apps -n fsm-system fsm-injector
```

### 2.2 部署 Nacos 微服务

```bash
make nacos-deploy
#PORT_FORWARD="18848:8848" make nacos-port-forward &

sleep 5

export c1_nacos_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=nacos -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_nacos_cluster_ip $c1_nacos_cluster_ip

export c1_nacos_external_ip="$(kubectl get svc -n default --field-selector metadata.name=nacos -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_nacos_external_ip $c1_nacos_external_ip

export c1_nacos_pod_ip="$(kubectl get pod -n default --selector app=nacos -o jsonpath='{.items[0].status.podIP}')"
echo c1_nacos_pod_ip $c1_nacos_pod_ip

WITH_MESH=false fsm_cluster_name=c1 replicas=1 make deploy-nacos-httpbin-curl
```

## 3 微服务融合

### 3.1 导入本集群 nacos 微服务

#### 3.1.1 部署 nacos connector(c1-nacos-to-c1-httpbin)

```bash
kubectl apply -n httpbin  -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-nacos-to-c1-httpbin
spec:
  httpAddr: $c1_nacos_cluster_ip:8848
  deriveNamespace: httpbin
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
export c1_curl_pod_name="$(kubectl get pod -n httpbin --selector app=curl -o jsonpath='{.items[0].metadata.name}')"
echo c1_curl_pod_name $c1_curl_pod_name
```

### 4.2 确认服务调用效果

**多次执行:**

```bash
kubectl exec -n httpbin $c1_curl_pod_name -c curl -- curl -s httpbin:14001
```

**正确返回结果类似于:**

```bash
c1-httpbin-8497f8477b-lbrbv
```

## 5 卸载 C1 集群

```bash
clusters="C1" make k3d-reset
```
