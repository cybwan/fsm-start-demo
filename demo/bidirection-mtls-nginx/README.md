# FSM bidirection mTLS Demo

## 1. Download and install the fsm command line tool

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.0.0
curl -L https://github.com/flomesh-io/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/fsm version
cp ./${system}-${arch}/fsm /usr/local/bin/
```

## 2. Install `fsm` Service mesh

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

## 3. Install Nginx Ingress

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

## 4. Bi-direction mTLS Test

### 4.1 Technical Concepts

<img src="https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/bidirection-mtls-nginx/Bidirectional_mTLS.png" alt="Bidirectional_mTLS" style="zoom:80%;" />

### 4.2 Deploy application POD

```bash
#Sample server service
kubectl create namespace egress-server
kubectl apply -n egress-server -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/bidirection-mtls-nginx/server.yaml

#Sample middle-ware service
kubectl create namespace egress-middle
fsm namespace add egress-middle
kubectl apply -n egress-middle -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/bidirection-mtls-nginx/middle.yaml

#Sample client
kubectl create namespace egress-client
kubectl apply -n egress-client -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/bidirection-mtls-nginx/client.yaml

#Wait for POD to start properly
kubectl wait --for=condition=ready pod -n egress-server -l app=server --timeout=180s
kubectl wait --for=condition=ready pod -n egress-middle -l app=middle --timeout=180s
kubectl wait --for=condition=ready pod -n egress-client -l app=client --timeout=180s
```

### 4.3 Scenario test case#1: HTTP Nginx & HTTP Ingress & mTLS Egress

#### 4.3.1 Test commands

Traffic flow:

Client --**http**--> Nginx Ingress Controller

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/hello
```

#### 4.3.2 Test results

The correct return result is similar to :

```bash
HTTP/1.1 404 Not Found
Date: Sun, 09 Oct 2022 08:36:48 GMT
Content-Type: text/html
Content-Length: 146
Connection: keep-alive

<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx</center>
</body>
</html>
```

#### 4.3.3 Setup Ingress Rules

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: egress-middle
  namespace: egress-middle
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: middle
            port:
              number: 8080
EOF
```

#### 4.3.4 Setup IngressBackend

```bash
kubectl apply -f - <<EOF
kind: IngressBackend
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: egress-middle
  namespace: egress-middle
spec:
  backends:
  - name: middle
    port:
      number: 8080 # targetPort of middle service
      protocol: http
  sources:
  - kind: Service
    namespace: ingress-nginx
    name: ingress-nginx-controller
EOF
```

#### 4.3.5 Test Commands

Traffic Flow:

Client --**http**--> Nginx Ingress --**http** --> sidecar --> Middle

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/hello
```

#### 4.3.6 Test Results

The correct return result is similar to :

```bash
HTTP/1.1 200 OK
Date: Sun, 09 Oct 2022 08:37:18 GMT
Content-Type: text/plain; charset=utf-8
Content-Length: 13
Connection: keep-alive
fsm-stats-namespace: egress-middle
fsm-stats-kind: Deployment
fsm-stats-name: middle
fsm-stats-pod: middle-5fc9f7b8b5-7txmc

hello world.
```

#### 4.3.7 Disable Egress Permissive mode

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge
```

#### 4.3.8 Enable Egress Policy

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
```

#### 4.3.9 Create Egress mTLS Secret

```bash
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/ca.crt -o ca.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.crt -o middle.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.key -o middle.key

kubectl create secret generic -n fsm-system egress-middle-cert \
  --from-file=ca.crt=./ca.crt \
  --from-file=tls.crt=./middle.crt \
  --from-file=tls.key=./middle.key 
```

#### 4.3.10 Setup Egress Policy

```bash
kubectl apply -f - <<EOF
kind: Egress
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: server-8443
  namespace: egress-middle
spec:
  sources:
  - kind: ServiceAccount
    name: middle
    namespace: egress-middle
    mtls:
      issuer: other
      cert:
        sn: 1
        expiration: 2030-1-1 00:00:00
        secret:
          name: egress-middle-cert
          namespace: fsm-system
  hosts:
  - server.egress-server.svc.cluster.local
  ports:
  - number: 8443
    protocol: http
EOF
```

#### 4.3.11 Test Commands

Traffic Flow:

Client --**http**--> Nginx Ingress --**http**--> sidecar --> Middle --> sidecar --**egress mtls**--> Server

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/time
```

#### 4.3.12 Test Results

The correct return result is similar to :

```bash
HTTP/1.1 200 OK
Date: Sun, 09 Oct 2022 08:38:03 GMT
Content-Type: text/plain; charset=utf-8
Content-Length: 74
Connection: keep-alive
fsm-stats-namespace: egress-middle
fsm-stats-kind: Deployment
fsm-stats-name: middle
fsm-stats-pod: middle-5fc9f7b8b5-7txmc

The current time: 2022-10-09 08:38:03.03610171 +0000 UTC m=+107.351638075
```

This business scenario is tested and the strategy is cleaned up to avoid affecting subsequent tests

```bash
kubectl delete ingress -n egress-middle egress-middle
kubectl delete ingressbackend -n egress-middle egress-middle
kubectl delete egress -n egress-middle server-8443
kubectl delete secrets -n fsm-system egress-middle-cert
```

### 4.4 Test Scenario#2: HTTP Nginx & mTLS Ingress & mTLS Egress

#### 4.4.1 Test Commands

Traffic flow:

Client --**http**--> Nginx Ingress Controller

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/hello
```

#### 4.4.2 Test Results

The correct return result is similar to :

```bash
HTTP/1.1 404 Not Found
Date: Sun, 09 Oct 2022 08:38:27 GMT
Content-Type: text/html
Content-Length: 146
Connection: keep-alive

<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx</center>
</body>
</html>
```

#### 4.4.3 Setup Ingress Controller Cert

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"certificate":{"ingressGateway":{"secret":{"name":"ingress-controller-cert","namespace":"fsm-system"},"subjectAltNames":["ingress-nginx.ingress-nginx.cluster.local"],"validityDuration":"24h"}}}}' --type=merge
```

#### 4.4.4 Setup Ingress Rules

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: egress-middle
  namespace: egress-middle
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    # proxy_ssl_name for a service is of the form <service-account>.<namespace>.cluster.local
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_ssl_name "middle.egress-middle.cluster.local";
    nginx.ingress.kubernetes.io/proxy-ssl-secret: "fsm-system/ingress-controller-cert"
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
            name: middle
            port:
              number: 8080
EOF
```

#### 4.4.5 Setup IngressBackend Policy

```bash
kubectl apply -f - <<EOF
kind: IngressBackend
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: egress-middle
  namespace: egress-middle
spec:
  backends:
  - name: middle
    port:
      number: 8080 # targetPort of middle service
      protocol: https
    tls:
      skipClientCertValidation: false
  sources:
  - kind: Service
    namespace: ingress-nginx
    name: ingress-nginx-controller
  - kind: AuthenticatedPrincipal
    name: ingress-nginx.ingress-nginx.cluster.local
EOF
```

#### 4.4.6 Test Commands

Traffic flow:

Client --**http**--> Nginx Ingress --**mtls** --> sidecar --> Middle

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/hello
```

#### 4.4.7 Test Results

The correct return result is similar to :

```bash
HTTP/1.1 200 OK
Date: Sun, 09 Oct 2022 08:39:02 GMT
Content-Type: text/plain; charset=utf-8
Content-Length: 13
Connection: keep-alive
fsm-stats-namespace: egress-middle
fsm-stats-kind: Deployment
fsm-stats-name: middle
fsm-stats-pod: middle-5fc9f7b8b5-7txmc

hello world.
```

#### 4.4.8 Disable Egress Permissive mode

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge
```

#### 4.4.9 Enable Egress Policy

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
```

#### 4.4.10 Create Egress mTLS Secret

```bash
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/ca.crt -o ca.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.crt -o middle.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.key -o middle.key

kubectl create secret generic -n fsm-system egress-middle-cert \
  --from-file=ca.crt=./ca.crt \
  --from-file=tls.crt=./middle.crt \
  --from-file=tls.key=./middle.key 
```

#### 4.4.11 Setup Egress Policy

```bash
kubectl apply -f - <<EOF
kind: Egress
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: server-8443
  namespace: egress-middle
spec:
  sources:
  - kind: ServiceAccount
    name: middle
    namespace: egress-middle
    mtls:
      issuer: other
      cert:
        sn: 1
        expiration: 2030-1-1 00:00:00
        secret:
          name: egress-middle-cert
          namespace: fsm-system
  hosts:
  - server.egress-server.svc.cluster.local
  ports:
  - number: 8443
    protocol: http
EOF
```

#### 4.4.12 Test Commands

Traffic flow:

Client --**http**--> Nginx Ingress --**mtls**--> sidecar --> Middle --> sidecar --**egress mtls**--> Server

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/time
```

#### 4.4.13 Test Results

The correct return result is similar to :

```bash
HTTP/1.1 200 OK
Date: Sun, 09 Oct 2022 08:39:42 GMT
Content-Type: text/plain; charset=utf-8
Content-Length: 75
Connection: keep-alive
fsm-stats-namespace: egress-middle
fsm-stats-kind: Deployment
fsm-stats-name: middle
fsm-stats-pod: middle-5fc9f7b8b5-7txmc

The current time: 2022-10-09 08:39:42.336230168 +0000 UTC m=+206.716581170
```

This business scenario is tested and the strategy is cleaned up to avoid affecting subsequent tests

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"certificate":{"ingressGateway":null}}}' --type=merge

kubectl delete ingress -n egress-middle egress-middle
kubectl delete ingressbackend -n egress-middle egress-middle
kubectl delete egress -n egress-middle server-8443
kubectl delete secrets -n fsm-system egress-middle-cert
```

### 4.5 Test Scenario#3：TLS Nginx & mTLS Ingress & mTLS Egress

#### 4.5.1 Test Commands

Traffic flow

Client --**http**--> Nginx Ingress Controller

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/hello
```

#### 4.5.2 Test Results

The correct return result is similar to :

```bash
HTTP/1.1 404 Not Found
Date: Sun, 09 Oct 2022 08:40:00 GMT
Content-Type: text/html
Content-Length: 146
Connection: keep-alive

<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx</center>
</body>
</html>
```

#### 4.5.3 Setup Ingress Controller Cert

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"certificate":{"ingressGateway":{"secret":{"name":"ingress-controller-cert","namespace":"fsm-system"},"subjectAltNames":["ingress-nginx.ingress-nginx.cluster.local"],"validityDuration":"24h"}}}}' --type=merge
```

#### 4.5.4 Create Nginx TLS Secret

```bash
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/nginx.crt -o nginx.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/nginx.key -o nginx.key

kubectl create secret tls -n egress-middle nginx-cert-secret \
  --cert=./nginx.crt \
  --key=./nginx.key 
```

#### 4.5.5 Setup Ingress Rules

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: egress-middle
  namespace: egress-middle
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    # proxy_ssl_name for a service is of the form <service-account>.<namespace>.cluster.local
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_ssl_name "middle.egress-middle.cluster.local";
    nginx.ingress.kubernetes.io/proxy-ssl-secret: "fsm-system/ingress-controller-cert"
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
            name: middle
            port:
              number: 8080
  tls:
  - hosts:
    - ingress-nginx-controller.ingress-nginx
    secretName: nginx-cert-secret
EOF
```

#### 4.5.6 Setup IngressBackend Policy

```bash
kubectl apply -f - <<EOF
kind: IngressBackend
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: egress-middle
  namespace: egress-middle
spec:
  backends:
  - name: middle
    port:
      number: 8080 # targetPort of middle service
      protocol: https
    tls:
      skipClientCertValidation: false
  sources:
  - kind: Service
    namespace: ingress-nginx
    name: ingress-nginx-controller
  - kind: AuthenticatedPrincipal
    name: ingress-nginx.ingress-nginx.cluster.local
EOF
```

#### 4.5.7 Test Commands

Traffic flow:

Client --**tls**--> Nginx Ingress --**mtls** --> sidecar --> Middle

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -ksi https://ingress-nginx-controller.ingress-nginx/hello --key /certs/client.key --cert /certs/client.crt
```

#### 4.5.8 Test Results

The correct return result is similar to :

```bash
HTTP/2 200 
date: Sun, 09 Oct 2022 08:40:40 GMT
content-type: text/plain; charset=utf-8
content-length: 13
fsm-stats-namespace: egress-middle
fsm-stats-kind: Deployment
fsm-stats-name: middle
fsm-stats-pod: middle-5fc9f7b8b5-7txmc
strict-transport-security: max-age=15724800; includeSubDomains

hello world.
```

#### 4.5.9 Disable Egress Permissive mode

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge
```

#### 4.5.10 Enable Egress Policy

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
```

#### 4.5.11 Create Egress mTLS Secret

```bash
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/ca.crt -o ca.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.crt -o middle.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.key -o middle.key

kubectl create secret generic -n fsm-system egress-middle-cert \
  --from-file=ca.crt=./ca.crt \
  --from-file=tls.crt=./middle.crt \
  --from-file=tls.key=./middle.key 
```

#### 4.5.12 Setup Egress Policy

```bash
kubectl apply -f - <<EOF
kind: Egress
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: server-8443
  namespace: egress-middle
spec:
  sources:
  - kind: ServiceAccount
    name: middle
    namespace: egress-middle
    mtls:
      issuer: other
      cert:
        sn: 1
        expiration: 2030-1-1 00:00:00
        secret:
          name: egress-middle-cert
          namespace: fsm-system
  hosts:
  - server.egress-server.svc.cluster.local
  ports:
  - number: 8443
    protocol: http
EOF
```

#### 4.5.13 Test Commands

Traffic flow:

Client --**tls**--> Nginx Ingress --**mtls**--> sidecar --> Middle --> sidecar --**egress mtls**--> Server

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -ksi https://ingress-nginx-controller.ingress-nginx/time --key /certs/client.key --cert /certs/client.crt
```

#### 4.5.14 Test Results

The correct return result is similar to :

```bash
HTTP/2 200 
date: Sun, 09 Oct 2022 08:41:21 GMT
content-type: text/plain; charset=utf-8
content-length: 75
fsm-stats-namespace: egress-middle
fsm-stats-kind: Deployment
fsm-stats-name: middle
fsm-stats-pod: middle-5fc9f7b8b5-7txmc
strict-transport-security: max-age=15724800; includeSubDomains

The current time: 2022-10-09 08:41:21.121578846 +0000 UTC m=+305.588353001
```

This business scenario is tested and the strategy is cleaned up to avoid affecting subsequent tests

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"certificate":{"ingressGateway":null}}}' --type=merge

kubectl delete ingress -n egress-middle egress-middle
kubectl delete ingressbackend -n egress-middle egress-middle
kubectl delete egress -n egress-middle server-8443
kubectl delete secrets -n fsm-system egress-middle-cert
kubectl delete secrets -n egress-middle nginx-cert-secret
```

### 4.6 Test Scenario#4：mTLS Nginx & mTLS Ingress & mTLS Egress

#### 4.6.1 Test Commands

Traffic flow:

Client --**http**--> Nginx Ingress Controller

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/hello
```

#### 4.6.2 Test Results

The correct return result is similar to :

```bash
HTTP/1.1 404 Not Found
Date: Sun, 09 Oct 2022 08:41:52 GMT
Content-Type: text/html
Content-Length: 146
Connection: keep-alive

<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx</center>
</body>
</html>
```

#### 4.6.3 Setup Ingress Controller Cert

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"certificate":{"ingressGateway":{"secret":{"name":"ingress-controller-cert","namespace":"fsm-system"},"subjectAltNames":["ingress-nginx.ingress-nginx.cluster.local"],"validityDuration":"24h"}}}}' --type=merge
```

#### 4.6.4 Create Nginx CA Secret

```bash
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/ca.crt -o ca.crt

kubectl create secret generic -n egress-middle nginx-ca-secret \
  --from-file=ca.crt=./ca.crt 
```

#### 4.6.5 Create Nginx TLS Secret

```bash
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/nginx.crt -o nginx.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/nginx.key -o nginx.key

kubectl create secret tls -n egress-middle nginx-cert-secret \
  --cert=./nginx.crt \
  --key=./nginx.key 
```

#### 4.6.6 Setup Ingress Rules

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: egress-middle
  namespace: egress-middle
  annotations:
    nginx.ingress.kubernetes.io/auth-tls-pass-certificate-to-upstream: "false"
    nginx.ingress.kubernetes.io/auth-tls-secret: egress-middle/nginx-ca-secret
    nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"
    nginx.ingress.kubernetes.io/auth-tls-verify-depth: "1"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    # proxy_ssl_name for a service is of the form <service-account>.<namespace>.cluster.local
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_ssl_name "middle.egress-middle.cluster.local";
    nginx.ingress.kubernetes.io/proxy-ssl-secret: "fsm-system/ingress-controller-cert"
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
            name: middle
            port:
              number: 8080
  tls:
  - hosts:
    - ingress-nginx-controller.ingress-nginx
    secretName: nginx-cert-secret
EOF
```

#### 4.6.7 Setup IngressBackend Policy

```bash
kubectl apply -f - <<EOF
kind: IngressBackend
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: egress-middle
  namespace: egress-middle
spec:
  backends:
  - name: middle
    port:
      number: 8080 # targetPort of middle service
      protocol: https
    tls:
      skipClientCertValidation: false
  sources:
  - kind: Service
    namespace: ingress-nginx
    name: ingress-nginx-controller
  - kind: AuthenticatedPrincipal
    name: ingress-nginx.ingress-nginx.cluster.local
EOF
```

#### 4.6.8 Test Commands

Traffic flow:

Client --**mtls**--> Nginx Ingress --**mtls** --> sidecar --> Middle

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -ksi https://ingress-nginx-controller.ingress-nginx/hello  --cacert /certs/ca.crt --key /certs/client.key --cert /certs/client.crt
```

#### 4.6.9 Test Results

The correct return result is similar to :

```bash
HTTP/2 200 
date: Sun, 09 Oct 2022 08:42:37 GMT
content-type: text/plain; charset=utf-8
content-length: 13
fsm-stats-namespace: egress-middle
fsm-stats-kind: Deployment
fsm-stats-name: middle
fsm-stats-pod: middle-5fc9f7b8b5-7txmc
strict-transport-security: max-age=15724800; includeSubDomains

hello world.
```

#### 4.6.10 Disable Egress Permissive mode

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge
```

#### 4.6.11 Enable Egress Policy

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
```

#### 4.6.12 Create Egress mTLS Secret

```bash
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/ca.crt -o ca.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.crt -o middle.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.key -o middle.key

kubectl create secret generic -n fsm-system egress-middle-cert \
  --from-file=ca.crt=./ca.crt \
  --from-file=tls.crt=./middle.crt \
  --from-file=tls.key=./middle.key 
```

#### 4.6.13 Setup Egress Policy

```bash
kubectl apply -f - <<EOF
kind: Egress
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: server-8443
  namespace: egress-middle
spec:
  sources:
  - kind: ServiceAccount
    name: middle
    namespace: egress-middle
    mtls:
      issuer: other
      cert:
        sn: 1
        expiration: 2030-1-1 00:00:00
        secret:
          name: egress-middle-cert
          namespace: fsm-system
  hosts:
  - server.egress-server.svc.cluster.local
  ports:
  - number: 8443
    protocol: http
EOF
```

#### 4.6.14 Test Commands

Traffic flow:

Client --**mtls**--> Nginx Ingress --**mtls**--> sidecar --> Middle --> sidecar --**egress mtls**--> Server

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -ksi https://ingress-nginx-controller.ingress-nginx/time --cacert /certs/ca.crt --key /certs/client.key --cert /certs/client.crt
```

#### 4.6.15 Test Results

The correct return result is similar to :

```bash
HTTP/2 200 
date: Sun, 09 Oct 2022 08:43:13 GMT
content-type: text/plain; charset=utf-8
content-length: 75
fsm-stats-namespace: egress-middle
fsm-stats-kind: Deployment
fsm-stats-name: middle
fsm-stats-pod: middle-5fc9f7b8b5-7txmc
strict-transport-security: max-age=15724800; includeSubDomains

The current time: 2022-10-09 08:43:13.241006879 +0000 UTC m=+417.741653620
```

This business scenario is tested and the strategy is cleaned up to avoid affecting subsequent tests

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"certificate":{"ingressGateway":null}}}' --type=merge

kubectl delete ingress -n egress-middle egress-middle
kubectl delete ingressbackend -n egress-middle egress-middle
kubectl delete egress -n egress-middle server-8443
kubectl delete secrets -n fsm-system egress-middle-cert
kubectl delete secrets -n egress-middle nginx-cert-secret
kubectl delete secrets -n egress-middle nginx-ca-secret
```

