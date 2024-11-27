# FSM Ingress 测试

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
    --set=fsm.image.registry=flomesh \
    --set=fsm.image.tag=1.0.0 \
    --set=fsm.image.pullPolicy=Always \
    --set=fsm.sidecarLogLevel=error \
    --set=fsm.controllerLogLevel=warn \
    --timeout=900s
```

## 3. 安装 Nginx Ingress

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm search repo ingress-nginx

kubectl create namespace ingress-nginx
helm install -n ingress-nginx ingress-nginx ingress-nginx/ingress-nginx --version=4.0.18 -f - <<EOF
{
  "controller": {
    "hostPort": {
      "enabled": true,
		},
		"service":  {
		  "type": "NodePort",
		},
	},
}
EOF

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=ingress-nginx \
  --timeout=180s
```

## 3. Nginx Ingress 测试

### 3.1 部署业务 POD

```bash
#模拟业务服务
kubectl create namespace httpbin
fsm namespace add httpbin
kubectl apply -n httpbin -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/ingress-nginx/httpbin.yaml

#模拟外部客户端
kubectl create namespace ext-curl
kubectl apply -n ext-curl -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/ingress-nginx/curl.yaml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n httpbin -l app=httpbin --timeout=180s
kubectl wait --for=condition=ready pod -n ext-curl -l app=curl --timeout=180s
```

### 3.2 HTTP Ingress测试

#### 3.2.1 测试指令

```bash
kubectl exec "$(kubectl get pod -n ext-curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n ext-curl -- curl -sI http://ingress-nginx-controller.ingress-nginx:80/get -H "Host: httpbin.org"
```

#### 3.2.2 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 404 Not Found
Date: Thu, 22 Sep 2022 04:06:04 GMT
Content-Type: text/html
Content-Length: 146
Connection: keep-alive
```

#### 3.2.3 设置 Ingress 策略

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: httpbin
  namespace: httpbin
spec:
  ingressClassName: nginx
  rules:
  - host: httpbin.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: httpbin
            port:
              number: 14001      
EOF
```

#### 3.2.4 设置 IngressBackend 策略

```bash
kubectl apply -f - <<EOF
kind: IngressBackend
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
    namespace: ingress-nginx
    name: ingress-nginx-controller
EOF
```

#### 3.2.5 测试指令

```bash
kubectl exec "$(kubectl get pod -n ext-curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n ext-curl -- curl -sI http://ingress-nginx-controller.ingress-nginx:80/get -H "Host: httpbin.org"
```

#### 3.2.6 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
Date: Thu, 22 Sep 2022 03:12:48 GMT
Content-Type: application/json
Content-Length: 349
Connection: keep-alive
access-control-allow-origin: *
access-control-allow-credentials: true
fsm-stats-namespace: httpbin
fsm-stats-kind: Deployment
fsm-stats-name: httpbin
fsm-stats-pod: httpbin-7c6464475-hmrb9
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete ingress -n httpbin httpbin
kubectl delete ingressbackend -n httpbin httpbin 
```

### 3.3 HTTPS Ingress测试

#### 3.3.1 测试指令

```bash
kubectl exec "$(kubectl get pod -n ext-curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n ext-curl -- curl -sI http://ingress-nginx-controller.ingress-nginx:80/get -H "Host: httpbin.org"
```

#### 3.3.2 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 404 Not Found
Date: Thu, 22 Sep 2022 04:06:04 GMT
Content-Type: text/html
Content-Length: 146
Connection: keep-alive
```

#### 3.3.2 设置 Ingress Controller 证书上下文

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"certificate":{"ingressGateway":{"secret":{"name":"fsm-nginx-client-cert","namespace":"fsm-system"},"subjectAltNames":["ingress-nginx.ingress-nginx.cluster.local"],"validityDuration":"24h"}}}}' --type=merge
```

#### 3.3.3 设置 Ingress 策略

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: httpbin
  namespace: httpbin
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    # proxy_ssl_name for a service is of the form <service-account>.<namespace>.cluster.local
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_ssl_name "httpbin.httpbin.cluster.local";
    nginx.ingress.kubernetes.io/proxy-ssl-secret: "fsm-system/fsm-nginx-client-cert"
    nginx.ingress.kubernetes.io/proxy-ssl-verify: "on"
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: httpbin
            port:
              number: 14001
EOF
```

#### 3.3.4 场景测试一：证书校验，可信Ingress证书

##### 3.3.4.1 设置 IngressBackend 策略

```bash
kubectl apply -f - <<EOF
apiVersion: policy.flomesh.io/v1alpha1
kind: IngressBackend
metadata:
  name: httpbin
  namespace: httpbin
spec:
  backends:
  - name: httpbin
    port:
      number: 14001 # targetPort of httpbin service
      protocol: https
    tls:
      skipClientCertValidation: false
  sources:
  - kind: Service
    name: ingress-nginx-controller
    namespace: ingress-nginx
  - kind: AuthenticatedPrincipal
    name: ingress-nginx.ingress-nginx.cluster.local
EOF
```

##### 3.3.4.2 测试指令

```bash
kubectl exec "$(kubectl get pod -n ext-curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n ext-curl -- curl -sI http://ingress-nginx-controller.ingress-nginx:80/get -H "Host: httpbin.org"
```

##### 3.3.4.3 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
Date: Thu, 22 Sep 2022 04:36:05 GMT
Content-Type: application/json
Content-Length: 321
Connection: keep-alive
access-control-allow-origin: *
access-control-allow-credentials: true
x-pipy-upstream-service-time: 2
```

#### 3.3.5 场景测试二：证书校验，不可信Ingress证书

##### 3.3.5.1 设置 IngressBackend 策略

```bash
kubectl apply -f - <<EOF
apiVersion: policy.flomesh.io/v1alpha1
kind: IngressBackend
metadata:
  name: httpbin
  namespace: httpbin
spec:
  backends:
  - name: httpbin
    port:
      number: 14001 # targetPort of httpbin service
      protocol: https
    tls:
      skipClientCertValidation: false
  sources:
  - kind: Service
    name: ingress-nginx-controller
    namespace: ingress-nginx
  - kind: AuthenticatedPrincipal
    name: untrusted-client.cluster.local # untrusted
EOF
```

##### 3.3.5.2 测试指令

```bash
kubectl exec "$(kubectl get pod -n ext-curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n ext-curl -- curl -sI http://ingress-nginx-controller.ingress-nginx:80/get -H "Host: httpbin.org"
```

##### 3.3.5.3 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 403 Forbidden
Date: Fri, 23 Sep 2022 04:52:11 GMT
Content-Type: text/plain
Content-Length: 19
Connection: keep-alive
```

#### 3.3.6 场景测试三：证书不校验，不可信Ingress证书

##### 3.3.6.1 设置 IngressBackend 策略

```bash
kubectl apply -f - <<EOF
apiVersion: policy.flomesh.io/v1alpha1
kind: IngressBackend
metadata:
  name: httpbin
  namespace: httpbin
spec:
  backends:
  - name: httpbin
    port:
      number: 14001 # targetPort of httpbin service
      protocol: https
    tls:
      skipClientCertValidation: true
  sources:
  - kind: Service
    name: ingress-nginx-controller
    namespace: ingress-nginx
  - kind: AuthenticatedPrincipal
    name: untrusted-client.cluster.local # untrusted
EOF
```

##### 3.3.6.2 测试指令

```bash
kubectl exec "$(kubectl get pod -n ext-curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n ext-curl -- curl -sI http://ingress-nginx-controller.ingress-nginx:80/get -H "Host: httpbin.org"
```

##### 3.3.6.3 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
Date: Fri, 23 Sep 2022 04:53:26 GMT
Content-Type: application/json
Content-Length: 320
Connection: keep-alive
access-control-allow-origin: *
access-control-allow-credentials: true
x-pipy-upstream-service-time: 1
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete ingress -n httpbin httpbin
kubectl delete ingressbackend -n httpbin httpbin
#helm uninstall ingress-nginx -n ingress-nginx
```



