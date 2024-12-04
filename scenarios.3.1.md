# 场景 HTTP 业务测试

## 1 部署 K8S 集群

```bash
make k3d-up
kubecm switch k3d-c0
```

## 2 部署Zookeeper服务

```bash
make zk-deploy
make zk-port-forward

kubectl create namespace demo
kubectl apply -n demo -f manifests/zookeeper/nebula/grcp.server.yaml
kubectl apply -n demo -f manifests/zookeeper/nebula/grcp.client.yaml
```

## 2 部署网格服务

```bash
fsm_cluster_name=C1 make deploy-fsm
```

## 3 HTTP 业务测试

### 3.1 部署 fgw

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
      port: 15001
      name: mesh
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

### 3.2 部署 HTTP 模拟服务

```bash
#模拟业务服务
kubectl create namespace mesh-in
fsm namespace add mesh-in
kubectl apply -n mesh-in -f manifests/curl.yaml
kubectl apply -n mesh-in -f manifests/httpbin.yaml
sleep 2
kubectl wait --all --for=condition=ready pod -n mesh-in -l app=curl --timeout=180s
kubectl wait --all --for=condition=ready pod -n mesh-in -l app=httpbin --timeout=180s

kubectl create namespace mesh-out
kubectl apply -n mesh-out -f manifests/curl.yaml
sleep 2
kubectl wait --all --for=condition=ready pod -n mesh-out -l app=curl --timeout=180s
```

### 3.3 部署 fgw connector

```bash
kubectl apply  -f - <<EOF
kind: GatewayConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: node-sidecar
spec:
  gatewayName: node-sidecar
  ingress:
    ipSelector: ClusterIP
    httpPort: 15001
  egress:
    ipSelector: ClusterIP
    httpPort: 15001
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - mesh-in
EOF
```

### 3.4 测试指令

#### 3.4.1 网格内服务互访

测试指令:

```bash
curl_pod="$(kubectl get pod -n mesh-in -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_pod} -n mesh-in -c curl -- curl -s httpbin.mesh-in
```

返回结果如下:

```bash
Hi, I am native httpbin by pipy!
```

#### 3.4.2 FGW 访问网格内服务

```bash
fgw_pod="$(kubectl get pod -n fsm-system -l app=fsm-gateway -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${fgw_pod} -n fsm-system -c curl -- curl -s httpbin.mesh-in
```

返回结果如下:

```bash
Hi, I am native httpbin by pipy!
```

#### 3.4.3 网格外通过 FGW 访问网格内服务

测试指令:

```bash
export fgw_pod_ip="$(kubectl get pod -n fsm-system --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
curl_pod="$(kubectl get pod -n mesh-out -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_pod} -n mesh-out -c curl -- curl -s -H "Host:httpbin.mesh-in" $fgw_pod_ip:15001
```

返回结果如下:

```bash
Hi, I am native httpbin by pipy!
```

#### 3.4.4 网格外访问网格内服务

测试指令:

```bash
curl_pod="$(kubectl get pod -n mesh-out -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_pod} -n mesh-out -c curl -- curl -s httpbin.mesh-in
```

返回结果如下:

```bash
Hi, I am native httpbin by pipy!
```

## 4 卸载 K8S 集群

```bash
make k3d-reset
```

## 5 参考资料

```url
https://blog.51cto.com/u_16099349/11082372
https://juejin.cn/post/7249522846211801147
```

