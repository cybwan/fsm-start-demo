# 场景 Nacos 多集群微服务融合测试

## 1 部署 SH HK 两个集群

```bash
clusters="SH HK" make k3d-up
```

## 2 部署服务

### 2.1 SH集群

```bash
kubecm switch k3d-SH
```

#### 2.1.1 部署 FSM Mesh

```bash
fsm_cluster_name=SH sidecar=PodLevel make deploy-fsm
```

#### 2.1.2 部署 Nacos 微服务

```bash
make nacos-deploy
#PORT_FORWARD="18848:8848" make nacos-port-forward &

export sh_nacos_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=nacos -o jsonpath='{.items[0].spec.clusterIP}')"
echo sh_nacos_cluster_ip $sh_nacos_cluster_ip

export sh_nacos_external_ip="$(kubectl get svc -n default --field-selector metadata.name=nacos -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo sh_nacos_external_ip $sh_nacos_external_ip

export sh_nacos_pod_ip="$(kubectl get pod -n default --selector app=nacos -o jsonpath='{.items[0].status.podIP}')"
echo sh_nacos_pod_ip $sh_nacos_pod_ip

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
    name: nacos
EOF

WITH_MESH=true make deploy-nacos-httpbin
```

### 2.2 HK集群

```bash
kubecm switch k3d-HK
```

#### 2.2.1 部署 FSM Mesh

```bash
fsm_cluster_name=HK sidecar=PodLevel make deploy-fsm
```

#### 2.2.1 部署 Nacos 微服务

```bash
make nacos-deploy
#PORT_FORWARD="28848:8848" make nacos-port-forward &

export hk_nacos_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=nacos -o jsonpath='{.items[0].spec.clusterIP}')"
echo hk_nacos_cluster_ip $hk_nacos_cluster_ip

export hk_nacos_external_ip="$(kubectl get svc -n default --field-selector metadata.name=nacos -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo hk_nacos_external_ip $hk_nacos_external_ip

export hk_nacos_pod_ip="$(kubectl get pod -n default --selector app=nacos -o jsonpath='{.items[0].status.podIP}')"
echo hk_nacos_pod_ip $hk_nacos_pod_ip

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
    name: nacos
EOF

WITH_MESH=true make deploy-nacos-httpbin
```

## 3 微服务融合

### 3.1 SH 集群

```bash
kubecm switch k3d-SH
```

#### 3.1.1 部署 fgw

```bash
export fsm_namespace=fsm-system
kubectl apply -n "$fsm_namespace" -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: k8s-sh-fgw
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
      port: 10090
      name: egrs-http
      allowedRoutes:
        namespaces:
          from: All
EOF

kubectl wait --all --for=condition=ready pod -n "$fsm_namespace" -l app=fsm-gateway --timeout=180s

until kubectl get service/fsm-gateway-fsm-system-k8s-sh-fgw-tcp -n $fsm_namespace --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

kubectl patch AccessControl -n fsm-policy global --type=json -p='[{"op": "add", "path": "/spec/sources/-", "value": {"kind":"Service","namespace":"fsm-system","name":"fsm-gateway-fsm-system-k8s-sh-fgw-tcp"}}]'

export sh_fgw_cluster_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-sh-fgw-tcp -o jsonpath='{.items[0].spec.clusterIP}')"
echo sh_fgw_cluster_ip $sh_fgw_cluster_ip

export sh_fgw_external_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-sh-fgw-tcp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo sh_fgw_external_ip $sh_fgw_external_ip

export sh_fgw_pod_ip="$(kubectl get pod -n $fsm_namespace --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo sh_fgw_pod_ip $sh_fgw_pod_ip
```

#### 3.1.2 部署 fgw connector

```bash
kubectl apply -n "$fsm_namespace" -f - <<EOF
kind: GatewayConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: sh-fgw
spec:
  gatewayName: k8s-sh-fgw
  ingress:
    ipSelector: ExternalIP
    httpPort: 10080
  egress:
    ipSelector: ClusterIP
    httpPort: 10090
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - derive-local
EOF
```

#### 3.1.3 创建 derive-local namespace

```bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"nacos"}}}'  --type=merge
```

#### 3.1.4 部署 nacos connector(sh-nacos-to-sh-derive-local)

```bash
kubectl apply -n "$fsm_namespace" -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: sh-nacos-to-sh-derive-local
spec:
  httpAddr: http://nacos.default:8848/nacos?grpcport=9848
  deriveNamespace: derive-local
  asInternalServices: true
  syncToK8S:
    enable: true
    appendLabels:
      flomesh.io/cluster: sh
    appendAnnotations:
      flomesh.io/region: sh
    metadataStrategy:
      enable: true
      labelConversions:
        io.flomesh.cluster: flomesh.io/cluster
      annotationConversions:
        io.flomesh.region: flomesh.io/region
    withGateway: 
      enable: true
    filterMetadatas: 
      - key: io.flomesh.region
        value: ""
  syncFromK8S:
    enable: false
EOF
```

#### 3.1.5 部署 nacos connector(sh-k8s-to-hk-nacos)

**sh k8s微服务同步到hk nacos**

```
kubectl apply -n "$fsm_namespace" -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: sh-k8s-to-hk-nacos
spec:
  httpAddr: http://$hk_nacos_external_ip:8848/nacos?grpcport=9848
  deriveNamespace: none
  syncToK8S:
    enable: false
  syncFromK8S:
    enable: true
    metadataStrategy:
      enable: true
      labelConversions:
        flomesh.io/cluster: io.flomesh.cluster
      annotationConversions:
        flomesh.io/region: io.flomesh.region
    withGateway: 
      enable: true
    allowK8sNamespaces:
      - derive-local
EOF
```
### 3.2 HK 集群

```bash
kubecm switch k3d-HK
```

#### 3.2.1 部署 fgw

```bash
export fsm_namespace=fsm-system
kubectl apply -n "$fsm_namespace" -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: k8s-hk-fgw
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
      port: 10090
      name: egrs-http
      allowedRoutes:
        namespaces:
          from: All
EOF

kubectl wait --all --for=condition=ready pod -n "$fsm_namespace" -l app=fsm-gateway --timeout=180s

until kubectl get service/fsm-gateway-fsm-system-k8s-hk-fgw-tcp -n $fsm_namespace --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

kubectl patch AccessControl -n fsm-policy global --type=json -p='[{"op": "add", "path": "/spec/sources/-", "value": {"kind":"Service","namespace":"fsm-system","name":"fsm-gateway-fsm-system-k8s-hk-fgw-tcp"}}]'

export hk_fgw_cluster_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-hk-fgw-tcp -o jsonpath='{.items[0].spec.clusterIP}')"
echo hk_fgw_cluster_ip $hk_fgw_cluster_ip

export hk_fgw_external_ip="$(kubectl get svc -n $fsm_namespace --field-selector metadata.name=fsm-gateway-fsm-system-k8s-hk-fgw-tcp -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo hk_fgw_external_ip $hk_fgw_external_ip

export hk_fgw_pod_ip="$(kubectl get pod -n $fsm_namespace --selector app=fsm-gateway -o jsonpath='{.items[0].status.podIP}')"
echo hk_fgw_pod_ip $hk_fgw_pod_ip
```

#### 3.2.2 部署 fgw connector

```bash
kubectl apply -n "$fsm_namespace" -f - <<EOF
kind: GatewayConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: hk-fgw
spec:
  gatewayName: k8s-hk-fgw
  ingress:
    ipSelector: ExternalIP
    httpPort: 10080
  egress:
    ipSelector: ClusterIP
    httpPort: 10090
  syncToFgw:
    enable: true
    allowK8sNamespaces:
      - derive-local
EOF
```

#### 3.2.3 创建 derive-local namespace

```bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"nacos"}}}'  --type=merge
```

#### 3.2.4 部署 nacos connector(hk-nacos-to-hk-derive-local)

```bash
kubectl apply -n "$fsm_namespace" -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: hk-nacos-to-hk-derive-local
spec:
  httpAddr: http://nacos.default:8848/nacos?grpcport=9848
  deriveNamespace: derive-local
  asInternalServices: true
  syncToK8S:
    enable: true
    appendLabels:
      flomesh.io/cluster: hk
    appendAnnotations:
      flomesh.io/region: hk
    metadataStrategy:
      enable: true
      labelConversions:
        io.flomesh.cluster: flomesh.io/cluster
      annotationConversions:
        io.flomesh.region: flomesh.io/region
    withGateway: 
      enable: true
    filterMetadatas: 
      - key: io.flomesh.region
        value: ""
  syncFromK8S:
    enable: false
EOF
```

#### 3.2.5 部署 nacos connector(hk-k8s-to-sh-nacos)

**hk k8s微服务同步到sh nacos**

```
kubectl apply -n "$fsm_namespace" -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: hk-k8s-to-sh-nacos
spec:
  httpAddr: http://$sh_nacos_external_ip:8848/nacos?grpcport=9848
  deriveNamespace: none
  syncToK8S:
    enable: false
  syncFromK8S:
    enable: true
    metadataStrategy:
      enable: true
      labelConversions:
        flomesh.io/cluster: io.flomesh.cluster
      annotationConversions:
        flomesh.io/region: io.flomesh.region
    withGateway: 
      enable: true
    allowK8sNamespaces:
      - derive-local
EOF
```
## 4 卸载 SH HK 两个集群

```bash
clusters="SH HK" make k3d-reset
```
