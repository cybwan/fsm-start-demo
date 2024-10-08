# 场景 Consul 跨集群微服务融合HA测试

## 1 部署 C1 集群

```bash
export clusters="C1"
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
WITH_MESH=true fsm_cluster_name=c1 replicas=1 make deploy-consul-curl
```

## 3 微服务融合

### 3.1 C1 集群

```bash
kubecm switch k3d-C1
```

#### 3.1.1 导入本集群 consul 微服务

##### 3.1.1.1 创建 derive-local namespace

```bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"consul"}}}'  --type=merge
```

##### 3.1.1.2 部署 consul connector(c1-consul-to-c1-derive-local)

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
    withGateway: 
      enable: false
  syncFromK8S:
    enable: false
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

## 5 集群调度策略

### 5.1 切换集群

```bash
kubecm switch k3d-C1
export c1_curl_pod_name="$(kubectl get pod -n curl --selector app=curl -o jsonpath='{.items[0].metadata.name}')"
echo c1_curl_pod_name $c1_curl_pod_name
```

### 5.2 查看集群调度策略

```bash
kubectl get meshconfigs -n fsm-system fsm-mesh-config -o jsonpath='{.spec.connector.lbType}'
```

### 5.3 FailOver

#### 5.3.1 设置集群调度策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"connector":{"lbType":"FailOver"}}}' --type=merge
```

#### 5.3.2 确认服务调用效果

**多次执行:**

```bash
kubectl exec -n curl $c1_curl_pod_name -c curl -- curl -s 127.0.0.1:14001
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
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"connector":{"lbType":"ActiveActive"}}}' --type=merge
```

#### 5.4.2 确认服务调用效果

**多次执行:**

```bash
kubectl exec -n curl $c1_curl_pod_name -c curl -- curl -s 127.0.0.1:14001
```

**正确返回结果类似于:**

```bash
c3-httpbin-5dd47d8645-ddhj5
c1-httpbin-5dd47d8645-mm2bg
c2-httpbin-5dd47d8645-lsdh8
```

## 6 卸载 C1 集群

```bash
export clusters="C1"
make k3d-reset
```
