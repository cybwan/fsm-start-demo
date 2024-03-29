

# FSM访问控制策略测试

## 1. 下载并安装 fsm 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.1.1
curl -L https://github.com/cybwan/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
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
    --set=fsm.image.registry=flomesh \
    --set=fsm.image.tag=1.1.1 \
    --set=fsm.image.pullPolicy=Always \
    --set=fsm.sidecarLogLevel=error \
    --set=fsm.controllerLogLevel=error \
    --timeout=900s
```

## 3. 访问控制策略测试

### 3.1 技术概念

在 FSM 中从未被 FSM 纳管的区域访问被 FSM 纳管的区域，有两种方法：

- Ingress，目前支持的 Ingress Controller：
  - FSM Pipy Ingress
  - Nginx Ingress
- Access Control，支持两种访问源类型：
  - Service
  - IPRange
- 支持的传输类型
  - 明文传输
  - 加密传输
    - mTLS
### 3.2 部署业务 POD

```bash
#模拟业务服务
kubectl create namespace httpbin
fsm namespace add httpbin
kubectl apply -n httpbin -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/access-control/httpbin.yaml

#模拟外部客户端
kubectl create namespace curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/access-control/curl.yaml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n httpbin -l app=httpbin --timeout=180s
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s
```

### 3.3 场景测试一：基于服务的访问控制，明文传输

#### 3.3.1 启用访问控制策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":true}}}'  --type=merge
```

#### 3.3.2 设置基于服务的访问控制策略

```bash
kubectl apply -f - <<EOF
kind: AccessControl
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: httpbin
  namespace: httpbin
spec:
  backends:
  - name: httpbin
    port:
      number: 14001 # targetPort of httpbin service
      protocol: http
  sources:
  - kind: Service
    namespace: curl
    name: curl
EOF
```

#### 3.3.3 测试指令

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -- curl -sI http://httpbin.httpbin:14001/get
```

#### 3.3.4 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: gunicorn/19.9.0
date: Sun, 18 Sep 2022 01:47:58 GMT
content-type: application/json
content-length: 267
access-control-allow-origin: *
access-control-allow-credentials: true
fsm-stats-namespace: httpbin
fsm-stats-kind: Deployment
fsm-stats-name: httpbin
fsm-stats-pod: httpbin-7c6464475-cf4qc
connection: keep-alive
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":false}}}'  --type=merge
kubectl delete accesscontrol -n httpbin httpbin
```

### 3.4 场景测试二：基于IP范围的访问控制，明文传输

#### 3.4.1 启用访问控制策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":true}}}'  --type=merge
```

#### 3.4.2 设置基于IP范围的访问控制策略

```bash
export fsm_namespace=fsm-system
curl_pod_ip="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].status.podIP}')"
kubectl apply -f - <<EOF
kind: AccessControl
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: httpbin
  namespace: httpbin
spec:
  backends:
  - name: httpbin
    port:
      number: 14001 # targetPort of httpbin service
      protocol: http
  sources:
  - kind: IPRange
    name: ${curl_pod_ip}/32
EOF
```

#### 3.4.3 测试指令

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -- curl -sI http://httpbin.httpbin:14001/get
```

#### 3.4.4 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: gunicorn/19.9.0
date: Sun, 18 Sep 2022 02:36:00 GMT
content-type: application/json
content-length: 267
access-control-allow-origin: *
access-control-allow-credentials: true
fsm-stats-namespace: httpbin
fsm-stats-kind: Deployment
fsm-stats-name: httpbin
fsm-stats-pod: httpbin-7c6464475-cf4qc
connection: keep-alive
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":false}}}'  --type=merge
kubectl delete accesscontrol -n httpbin httpbin
```

### 3.5 场景测试三：基于服务的访问控制，mTLS传输

#### 3.5.1 启用访问控制策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":true}}}'  --type=merge
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessCertPolicy":true}}}'  --type=merge
```

#### 3.5.2 为客户端创建证书 Secret

```bash
kubectl apply -f - <<EOF
kind: AccessCert
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: curl-mtls-cert
  namespace: httpbin
spec:
  subjectAltNames:
  - curl.curl.cluster.local
  secret:
    name: curl-mtls-secret
    namespace: curl
EOF
```

#### 3.5.3 客户端挂在证书 Secret

```bash
#模拟外部客户端
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/access-control/curl-mtls.yaml

#等待依赖的 POD 正常启动
```

#### 3.5.4 设置基于服务的访问控制策略

```bash
export fsm_namespace=fsm-system
kubectl apply -f - <<EOF
kind: AccessControl
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: httpbin
  namespace: httpbin
spec:
  backends:
  - name: httpbin
    port:
      number: 14001 # targetPort of httpbin service
      protocol: http
    tls:
      skipClientCertValidation: false
  sources:
  - kind: Service
    namespace: curl
    name: curl
  - kind: AuthenticatedPrincipal
    name: curl.curl.cluster.local
EOF
```

#### 3.5.5 测试指令

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -- curl -vsI https://httpbin.httpbin:14001/get --cacert /certs/ca.crt --key /certs/tls.key --cert /certs/tls.crt
```

#### 3.5.6 测试结果

正确返回结果类似于:

```bash
HTTP/2 200 
server: gunicorn
date: Tue, 11 Oct 2022 01:36:00 GMT
content-type: application/json
content-length: 267
access-control-allow-origin: *
access-control-allow-credentials: true
fsm-stats-namespace: httpbin
fsm-stats-kind: Deployment
fsm-stats-name: httpbin
fsm-stats-pod: httpbin-77dcf49495-tshft
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
export fsm_namespace=fsm-system
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/access-control/curl.yaml
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":false}}}'  --type=merge
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessCertPolicy":false}}}'  --type=merge
kubectl delete accesscontrol -n httpbin httpbin
kubectl delete accesscerts -n httpbin curl-mtls-cert
```

### 3.6 场景测试四：基于IP范围的访问控制，mTLS传输

#### 3.6.1 启用访问控制策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":true}}}'  --type=merge
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessCertPolicy":true}}}'  --type=merge
```

#### 3.6.2 为客户端创建证书 Secret

```bash
kubectl apply -f - <<EOF
kind: AccessCert
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: curl-mtls-cert
  namespace: httpbin
spec:
  subjectAltNames:
  - curl.curl.cluster.local
  secret:
    name: curl-mtls-secret
    namespace: curl
EOF
```

#### 3.6.3 客户端挂在证书 Secret

```bash
#模拟外部客户端
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/access-control/curl-mtls.yaml

#等待依赖的 POD 正常启动
```

#### 3.6.4 设置基于IP范围的访问控制策略

```bash
export fsm_namespace=fsm-system
curl_pod_ip="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].status.podIP}')"
kubectl apply -f - <<EOF
kind: AccessControl
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: httpbin
  namespace: httpbin
spec:
  backends:
  - name: httpbin
    port:
      number: 14001 # targetPort of httpbin service
      protocol: http
    tls:
      skipClientCertValidation: false
  sources:
  - kind: IPRange
    name: ${curl_pod_ip}/32
  - kind: AuthenticatedPrincipal
    name: curl.curl.cluster.local
EOF
```

#### 3.6.5 测试指令

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -- curl -ksI https://httpbin.httpbin:14001/get --cacert /certs/ca.crt --key /certs/tls.key --cert /certs/tls.crt
```

#### 3.6.6 测试结果

正确返回结果类似于:

```bash
HTTP/2 200 
server: gunicorn
date: Tue, 11 Oct 2022 01:42:01 GMT
content-type: application/json
content-length: 267
access-control-allow-origin: *
access-control-allow-credentials: true
fsm-stats-namespace: httpbin
fsm-stats-kind: Deployment
fsm-stats-name: httpbin
fsm-stats-pod: httpbin-77dcf49495-tshft
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
export fsm_namespace=fsm-system
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/access-control/curl.yaml
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":false}}}'  --type=merge
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessCertPolicy":false}}}'  --type=merge
kubectl delete accesscontrol -n httpbin httpbin
kubectl delete accesscerts -n httpbin curl-mtls-cert
```

