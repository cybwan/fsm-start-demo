# 场景 Eureka 单集群微服务融合测试

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

kubectl apply -n fsm-system -f - <<EOF
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: ListenerFilter
metadata:
  name: node-sidecar-accesslog
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

### 2.4 部署 eureka 服务

```bash
make eureka-deploy
#PORT_FORWARD="18761:8761" make eureka-port-forward &

export c1_eureka_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=eureka -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_eureka_cluster_ip $c1_eureka_cluster_ip

export c1_eureka_external_ip="$(kubectl get svc -n default --field-selector metadata.name=eureka -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_eureka_external_ip $c1_eureka_external_ip

export c1_eureka_pod_ip="$(kubectl get pod -n default --selector app=eureka -o jsonpath='{.items[0].status.podIP}')"
echo c1_eureka_pod_ip $c1_eureka_pod_ip
```

### 2.5 配置 eureka 服务访问控制策略

```bash
kubectl create namespace fsm-policy
fsm namespace add fsm-policy

kubectl apply -n fsm-policy -f - <<EOF
kind: AccessControl
apiVersion: xnetwork.flomesh.io/v1alpha1
metadata:
  name: global
spec:
  services:
  - namespace: default
    name: eureka
EOF
```

### 2.6 创建 derive-eureka namespace

```bash
kubectl create namespace derive-eureka
fsm namespace add derive-eureka
kubectl patch namespace derive-eureka -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"eureka"}}}'  --type=merge
```

### 2.7 部署 eureka connector(c1-eureka-to-c1-derive-eureka)

```
kubectl apply -n fsm-system -f - <<EOF
kind: EurekaConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-eureka-to-c1-derive-eureka
spec:
  httpAddr: http://$c1_eureka_cluster_ip:8761/eureka
  deriveNamespace: derive-eureka
  asInternalServices: true
  syncToK8S:
    enable: true
  syncFromK8S:
    enable: false
EOF
```

### 2.8 部署 fgw connector

```bash
kubectl apply -n fsm-system -f - <<EOF
kind: GatewayConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: node-sidecar
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
      - derive-eureka
EOF
```

### 2.9 部署 eureka 微服务

```bash
WITH_MESH=true fsm_cluster_name=c1 replicas=2 make deploy-eureka-httpbin
WITH_MESH=true fsm_cluster_name=c1 replicas=1 make deploy-eureka-curl
```

## 3 服务调用效果

### 3.1 切换集群

```bash
kubecm switch k3d-C1
export c1_curl_pod_name="$(kubectl get pod -n curl --selector app=curl -o jsonpath='{.items[0].metadata.name}')"
echo c1_curl_pod_name $c1_curl_pod_name
```

### 3.2 确认服务调用效果

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

## 4 卸载 C1 集群

```bash
clusters="C1" make k3d-reset
```
