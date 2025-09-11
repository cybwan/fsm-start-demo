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

fsm_cluster_name=sh \
region=sh \
ha_service=true \
WITH_MESH=true make deploy-nacos-httpbin

fsm_cluster_name=sh \
region=sh \
ha_service=false \
WITH_MESH=true make deploy-nacos-curl
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

fsm_cluster_name=hk \
region=hk \
ha_service=true \
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

#### 3.1.3 部署 connector-shnacos-shk8slocal

##### 3.1.3.1 创建 derive-local namespace

```bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"nacos"}}}'  --type=merge
```

##### 3.1.3.2 部署 nacos connector

```bash
kubectl apply -n "$fsm_namespace" -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: connector-shnacos-shk8slocal
spec:
  httpAddr: http://nacos.default:8848/nacos?grpcport=9848
  deriveNamespace: derive-local
  asInternalServices: true
  syncToK8S:
    enable: true
    withGateway: 
      enable: true
    metadataStrategy:
      enable: true
      labelConversions:
        ha_service: ha_service
        organization: organization
    filterMetadatas: 
      - key: region
        value: sh
  syncFromK8S:
    enable: false
EOF
```

#### 3.1.4 部署 connector-shnacos-shk8sother

##### 3.1.4.1 创建 derive-other namespace

```bash
kubectl create namespace derive-other
fsm namespace add derive-other
kubectl patch namespace derive-other -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"nacos"}}}'  --type=merge
```

##### 3.1.3.2 部署 nacos connector

```bash
kubectl apply -n "$fsm_namespace" -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: connector-shnacos-shk8sother
spec:
  httpAddr: http://nacos.default:8848/nacos?grpcport=9848
  deriveNamespace: derive-other
  asInternalServices: false
  syncToK8S:
    enable: true
    withGateway: 
      enable: true
    metadataStrategy:
      enable: true
      labelConversions:
        ha_service: ha_service
        organization: organization
    filterMetadatas: 
      - key: region
        value: hk
  syncFromK8S:
    enable: false
EOF
```

#### 3.1.5 部署 connector-shk8slocal-hknacos

**sh k8s微服务同步到hk nacos**

```
kubectl apply -n "$fsm_namespace" -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: connector-shk8slocal-hknacos
spec:
  httpAddr: http://$hk_nacos_external_ip:8848/nacos?grpcport=9848
  deriveNamespace: none
  syncToK8S:
    enable: false
  syncFromK8S: 
    enable: true
    allowK8sNamespaces:
      - derive-local
    withGateway: 
      enable: true
    appendMetadatas:
      - key: region
        value: sh
    metadataStrategy:
      enable: true
      labelConversions:
        ha_service: ha_service
        organization: organization
    filterLabels: 
      - key: ha_service
        value: "true"
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

#### 3.2.3 部署 connector-hknacos-hkk8slocal

##### 3.2.3.1 创建 derive-local namespace

```bash
kubectl create namespace derive-local
fsm namespace add derive-local
kubectl patch namespace derive-local -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"nacos"}}}'  --type=merge
```

##### 3.2.3.2 部署 nacos connector

```bash
kubectl apply -n "$fsm_namespace" -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: connector-hknacos-hkk8slocal
spec:
  httpAddr: http://nacos.default:8848/nacos?grpcport=9848
  deriveNamespace: derive-local
  asInternalServices: true
  syncToK8S:
    enable: true
    withGateway: 
      enable: true
    metadataStrategy:
      enable: true
      labelConversions:
        ha_service: ha_service
        organization: organization
    filterMetadatas: 
      - key: region
        value: hk
  syncFromK8S:
    enable: false
EOF
```

#### 3.1.4 部署 connector-hknacos-hkk8sother

##### 3.1.4.1 创建 derive-other namespace

```bash
kubectl create namespace derive-other
fsm namespace add derive-other
kubectl patch namespace derive-other -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"nacos"}}}'  --type=merge
```

##### 3.1.3.2 部署 nacos connector

```bash
kubectl apply -n "$fsm_namespace" -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: connector-hknacos-hkk8sother
spec:
  httpAddr: http://nacos.default:8848/nacos?grpcport=9848
  deriveNamespace: derive-other
  asInternalServices: false
  syncToK8S:
    enable: true
    withGateway: 
      enable: true
    metadataStrategy:
      enable: true
      labelConversions:
        ha_service: ha_service
        organization: organization
    filterMetadatas: 
      - key: region
        value: hk
  syncFromK8S:
    enable: false
EOF
```

#### 3.1.5 部署 connector-hkk8slocal-shnacos

**hk k8s微服务同步到sh nacos**

```
kubectl apply -n "$fsm_namespace" -f - <<EOF
kind: NacosConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: connector-hkk8slocal-shnacos
spec:
  httpAddr: http://$sh_nacos_external_ip:8848/nacos?grpcport=9848
  deriveNamespace: none
  syncToK8S:
    enable: false
  syncFromK8S: 
    enable: true
    allowK8sNamespaces:
      - derive-local
    withGateway: 
      enable: true
    appendMetadatas:
      - key: region
        value: hk
    metadataStrategy:
      enable: true
      labelConversions:
        ha_service: ha_service
        organization: organization
    filterLabels: 
      - key: ha_service
        value: "true"
EOF
```
## 4 跨集群HA 配置

### 4.1 SH 集群

```bash
kubecm switch k3d-SH
```

#### 4.1.1 配置跨集群策略

```bash
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"connector":{"lb":{"type":"FailOver","masterNamespace":"derive-local","slaveNamespaces":["derive-other"]}}}}' --type=merge
```

#### 4.1.2 启用proxy-tag插件

```bash 
kubectl apply  -n "$fsm_namespace" -f - <<EOF
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: FilterConfig
metadata:
 name:  proxytag-fc
spec:
  config: |
    proxyTag:
      dstHostHeader: "fgw-forwarded-service"
---
apiVersion: extension.gateway.flomesh.io/v1alpha1
kind: ListenerFilter
metadata:
 name: proxytag-outbound
spec:
 type: ProxyTag
 targetRefs:
   - group: gateway.networking.k8s.io
     kind: Gateway
     name: k8s-sh-fgw
     port: 10090
 configRef:
   group: extension.gateway.flomesh.io
   kind: FilterConfig
   name: proxytag-fc
EOF
```

#### 4.1.3 配置默认路由

```bash 
kubectl apply -n derive-other -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: 
  name: default-route-in
spec:
  parentRefs:
  - name: fgw
    namespace: $fsm_namespace
    port: 10080
  rules:
    - filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - name: "fgw-forward"
                value: "true"
      backendRefs:
        - name: k8s-sh-fgw
          port: 10080
      matches:
        - headers:
          - name: "fgw-forward"
            value: "^$"
            type: RegularExpression
EOF

kubectl apply -n derive-other -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: 
  name: default-route-out
spec:
  parentRefs:
  - name: fgw
    namespace: flomesh-test
    port: 10090
  rules:
    - filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - name: "fgw-forward"
                value: "true"
      backendRefs:
        - name: fgw-hk
          port: 10080
      matches:
        - headers:
          - name: "fgw-forward"
            value: "^$"
            type: RegularExpression
EOF
```

## 5 测试

```bash
export curl_pod_name="$(kubectl get pod -n curl --selector app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec -it -n curl $curl_pod_name -c curl -- sh
echo $(curl httpbin:14001 -s)

export curl_pod_name="$(kubectl get pod -n curl --selector app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec -it -n curl $curl_pod_name -c sidecar -- sh
curl 127.0.0.1:15000/config_dump
```

## 6 卸载 SH HK 两个集群

```bash
clusters="SH HK" make k3d-reset
```
