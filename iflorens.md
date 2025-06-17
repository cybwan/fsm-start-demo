# 场景 Nacos 微服务整合

## 1 部署 k3d 集群

```bash
clusters="C1" make k3d-up
```

## 2 部署服务

```bash
kubecm switch k3d-C1
```

### 2.1 部署 FSM Mesh

```bash
fsm_cluster_name=C1 fsm_namespace=flomesh-test make deploy-fsm
```

### 2.2 部署 Nacos 服务

```bash
make nacos-deploy

PORT_FORWARD="8848:8848" make nacos-port-forward &

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
    namespace: flomesh-test
    name: nacos
EOF

kubectl create namespace iflorens-test
fsm namespace add iflorens-test
kubectl apply -n iflorens-test -f ./manifests/flomesh-demo.yaml

export DEMO_POD=$(kubectl get pods --selector app=flomesh-demo -n iflorens-test --no-headers | grep 'Running' | awk 'NR==1{print $1}')
kubectl exec -it "$DEMO_POD" -n iflorens-test -c flomesh-demo-container -- bash
java -jar flomesh-demo.jar  --spring.config.location=file:/conf/application.yaml

kubectl rollout restart deployment -n iflorens-test flomesh-demo
```

### 2.3 创建 derive-nacos namespace

```bash
kubectl create namespace derive-nacos
fsm namespace add derive-nacos
kubectl patch namespace derive-nacos -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"nacos"}}}'  --type=merge
```

### 2.4 部署 nacos connector(c1-nacos-to-c1-derive-nacos)

```
kubectl apply  -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-nacos-to-c1-derive-nacos
spec:
  auth:
    username: nacos
    password: nacos
  httpAddr: $c1_nacos_cluster_ip:8848
  deriveNamespace: derive-nacos
  asInternalServices: true
  syncToK8S:
    enable: true
  syncFromK8S:
    enable: false
EOF
```

### 2.7 部署 Nacos 微服务

```bash
WITH_MESH=true make deploy-nacos-httpbin
WITH_MESH=true make deploy-nacos-curl
```

## 3 确认服务调用效果

转发 curl 服务端口:

```bash
PORT_FORWARD="14001:14001" make curl-port-forward &
```

测试指令:

```bash
curl http://127.0.0.1:14001 -v
```

确认运行效果,返回:

```bash
*   Trying 127.0.0.1:14001...
* Connected to 127.0.0.1 (127.0.0.1) port 14001
> GET / HTTP/1.1
> Host: 127.0.0.1:14001
> User-Agent: curl/8.4.0
> Handling connection for 14001
Accept: */*
> 
< HTTP/1.1 200 
< Content-Type: text/plain;charset=UTF-8
< Content-Length: 24
< Date: Thu, 09 May 2024 12:05:12 GMT
< 
* Connection #0 to host 127.0.0.1 left intact
httpbin-6fdb4c9544-kb94g%
```

## 4 卸载 k3d 集群

```bash
clusters="C1" make k3d-reset
```
