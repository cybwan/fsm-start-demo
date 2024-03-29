# FSM Retry 测试

## 1. 下载并安装 fsm 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.0.0
curl -L https://github.com/flomesh-io/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/fsm version
cp ./${system}-${arch}/fsm /usr/local/bin/
```

## 2. 安装 fsm

```bash
export fsm_namespace=fsm-system 
export fsm_mesh_name=fsm 

fsm install \
    --mesh-name "$fsm_mesh_name" \
    --fsm-namespace "$fsm_namespace" \
    --set=fsm.certificateProvider.kind=tresor \
    --set=fsm.image.registry=localhost:5000/flomesh \
    --set=fsm.image.tag=latest \
    --set=fsm.image.pullPolicy=Always \
    --set=fsm.sidecarLogLevel=error \
    --set=fsm.controllerLogLevel=warn \
    --set=fsm.enablePermissiveTrafficPolicy=true \
    --set=fsm.certificateProvider.serviceCertValidityDuration=5m \
    --timeout=900s
```

## 3. 重试策略测试

### 3.2 部署业务 POD

```bash
#模拟业务服务
kubectl create namespace httpbin
fsm namespace add httpbin
kubectl apply -n httpbin -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/retry/httpbin.yaml

#模拟客户端
kubectl create namespace retry
fsm namespace add retry
kubectl apply -n retry -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/retry/curl.yaml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n httpbin -l app=httpbin --timeout=180s
kubectl wait --for=condition=ready pod -n retry -l app=curl --timeout=180s
```

### 3.3 场景测试一：重试到被 FSM 纳管的服务

### 3.3.3 测试指令

```bash
curl_client="$(kubectl get pod -n retry -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$curl_client" -n retry -c curl -- curl -sI httpbin.httpbin.svc.cluster.local:14001
```

### 3.3.4 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 503 SERVICE
server: gunicorn/19.9.0
date: Wed, 21 Sep 2022 08:29:00 GMT
content-type: text/html; charset=utf-8
access-control-allow-origin: *
access-control-allow-credentials: true
content-length: 0
connection: keep-alive
```

### 3.3.5 观察统计指标

操作指令:

```bash
curl_client="$(kubectl get pod -n retry -l app=curl -o jsonpath='{.items[0].metadata.name}')"
fsm proxy get stats -n retry "$curl_client" | grep upstream_rq_retry
```

统计指标值应不变化:

```bash
cluster.httpbin/httpbin|14001.upstream_rq_retry: 4
cluster.httpbin/httpbin|14001.upstream_rq_retry_backoff_exponential: 4
cluster.httpbin/httpbin|14001.upstream_rq_retry_backoff_ratelimited: 0
cluster.httpbin/httpbin|14001.upstream_rq_retry_limit_exceeded: 1
cluster.httpbin/httpbin|14001.upstream_rq_retry_overflow: 0
cluster.httpbin/httpbin|14001.upstream_rq_retry_success: 0
```

### 3.3.6 测试指令

```bash
curl_client="$(kubectl get pod -n retry -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$curl_client" -n retry -c curl -- curl -sI httpbin.httpbin.svc.cluster.local:14001/status/404
```

### 3.3.7 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 404 NOT
server: gunicorn/19.9.0
date: Wed, 21 Sep 2022 08:50:21 GMT
content-type: text/html; charset=utf-8
access-control-allow-origin: *
access-control-allow-credentials: true
content-length: 0
connection: keep-alive
```

### 3.3.8 观察统计指标

操作指令:

```bash
curl_client="$(kubectl get pod -n retry -l app=curl -o jsonpath='{.items[0].metadata.name}')"
fsm proxy get stats -n retry "$curl_client" | grep upstream_rq_retry
```

统计指标值应不变化:

```bash
cluster.httpbin/httpbin|14001.upstream_rq_retry: 4
cluster.httpbin/httpbin|14001.upstream_rq_retry_backoff_exponential: 4
cluster.httpbin/httpbin|14001.upstream_rq_retry_backoff_ratelimited: 0
cluster.httpbin/httpbin|14001.upstream_rq_retry_limit_exceeded: 1
cluster.httpbin/httpbin|14001.upstream_rq_retry_overflow: 0
cluster.httpbin/httpbin|14001.upstream_rq_retry_success: 0
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubeexport fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableRetryPolicy":false}}}'  --type=merge
kubectl delete retry -n retry retry
```

### 3.4 场景测试二：重试到未被 FSM 纳管的服务

### 3.4.1 启用Egress目的策略模式

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
```

### 3.4.2 设置Egress目的策略模式

```bash
kubectl apply -f - <<EOF
kind: Egress
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: httpbin-14001
  namespace: retry
spec:
  sources:
  - kind: ServiceAccount
    name: curl
    namespace: retry
  hosts:
  - httpbin.httpbin-ext.svc.cluster.local
  ports:
  - number: 14001
    protocol: http
EOF
```

### 3.4.3 启用重试策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableRetryPolicy":true}}}'  --type=merge
```

### 3.4.4 设置重试策略

```bash
kubectl apply -f - <<EOF
kind: Retry
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: retry
  namespace: retry
spec:
  source:
    kind: ServiceAccount
    name: curl
    namespace: retry
  destinations:
  - kind: Service
    name: httpbin
    namespace: httpbin-ext
  retryPolicy:
    retryOn: "5xx"
    perTryTimeout: 1s
    numRetries: 4
    retryBackoffBaseInterval: 1s
EOF
```

### 3.4.5 测试指令

```bash
curl_client="$(kubectl get pod -n retry -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$curl_client" -n retry -c curl -- curl -sI httpbin.httpbin-ext.svc.cluster.local:14001/status/503
```

### 3.4.6 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 503 SERVICE
server: gunicorn/19.9.0
date: Wed, 21 Sep 2022 12:09:05 GMT
content-type: text/html; charset=utf-8
access-control-allow-origin: *
access-control-allow-credentials: true
content-length: 0
connection: keep-alive
```


