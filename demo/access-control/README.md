
# FSM Access Control Test

## 1. Download and install the `fsm` command line tool

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.0.0
curl -L https://github.com/flomesh-io/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/fsm version
cp ./${system}-${arch}/fsm /usr/local/bin/
```

## 2. Install `fsm` Service Mesh

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
    --set=fsm.enableEgress=false \
    --set=fsm.sidecarLogLevel=error \
    --set=fsm.controllerLogLevel=warn \
    --timeout=900s
```

## 3. Access Control Policy Testing

### 3.1 Technical concepts

To access `fsm` service mesh managed services from non mesh, you are provided with two methods:

- **Ingress** currently supported by the Ingress Controller.
  - FSM Pipy Ingress
  - Nginx Ingress
- **Access Control** which supports two access source types:
  - Service
  - IPRange


### 3.2 Deploy business POD

```bash
#Simulate business service
kubectl create namespace httpbin
fsm namespace add httpbin
kubectl apply -n httpbin -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/access-control/httpbin.yaml

#Simulate external client
kubectl create namespace curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/access-control/curl.yaml

#Wait for the dependent POD to start normally
kubectl wait --for=condition=ready pod -n httpbin -l app=httpbin --timeout=180s
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s
```

### 3.3 Scenario test case#1: service-based access control

#### 3.3.1 Enabling access control policies

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":true}}}'  --type=merge
```

#### 3.3.2 Setting up service-based access control policies

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
  sources:
  - kind: Service
    namespace: curl
    name: curl
EOF
```

#### 3.3.3 Test commands

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -- curl -sI http://httpbin.httpbin:14001/get
```

#### 3.3.4 Test Results

The correct return result might look similar to :

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

This business scenario is tested and the strategy is cleaned up to avoid affecting subsequent tests

```bash
kubeexport fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":false}}}'  --type=merge
kubectl delete accesscontrol -n httpbin httpbin
```

### 3.4 Scenario test case#2: IP range-based access control

#### 3.4.1 Enabling access control policies

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":true}}}'  --type=merge
```

#### 3.4.2 Setting IP range-based access control policies

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
  sources:
  - kind: IPRange
    name: 10.244.1.4/32
EOF
```

#### 3.4.3 Test commands

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -- curl -sI http://httpbin.httpbin:14001/get
```

#### 3.4.4 Test Results

The correct return result might look similar to :

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

This business scenario is tested and the strategy is cleaned up to avoid affecting subsequent tests

```bash
kubeexport fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":false}}}'  --type=merge
kubectl delete accesscontrol -n httpbin httpbin
```