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
fsm_cluster_name=C1 sidecar=PodLevel make deploy-fsm

# 无须 injector, 删除 injector
kubectl delete deployments.apps -n fsm-system fsm-injector
```

### 2.3 部署 Eureka 微服务

```bash
make eureka-deploy
#PORT_FORWARD="18761:8761" make eureka-port-forward &

export c1_eureka_cluster_ip="$(kubectl get svc -n default --field-selector metadata.name=eureka -o jsonpath='{.items[0].spec.clusterIP}')"
echo c1_eureka_cluster_ip $c1_eureka_cluster_ip

export c1_eureka_external_ip="$(kubectl get svc -n default --field-selector metadata.name=eureka -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo c1_eureka_external_ip $c1_eureka_external_ip

export c1_eureka_pod_ip="$(kubectl get pod -n default --selector app=eureka -o jsonpath='{.items[0].status.podIP}')"
echo c1_eureka_pod_ip $c1_eureka_pod_ip

WITH_MESH=false fsm_cluster_name=c1 replicas=2 make deploy-eureka-httpbin
WITH_MESH=false fsm_cluster_name=c1 replicas=1 make deploy-eureka-curl
```

## 3 微服务融合

### 3.1 导入本集群 eureka 微服务

#### 3.1.1 部署 eureka connector(c1-eureka-to-c1-curl)

```
kubectl apply -n fsm-system -f - <<EOF
kind: EurekaConnector
apiVersion: connector.flomesh.io/v1alpha1
metadata:
  name: c1-eureka-to-c1-curl
spec:
  httpAddr: http://$c1_eureka_cluster_ip:8761/eureka
  deriveNamespace: curl
  syncToK8S:
    enable: true
    filterIpRanges:
      - 10.101.0.0/16
    withGateway: 
      enable: false
  syncFromK8S:
    enable: false
EOF
```

## 4 服务调用效果

### 4.1 切换集群

```bash
kubecm switch k3d-C1
export c1_curl_pod_name="$(kubectl get pod -n curl --selector app=curl -o jsonpath='{.items[0].metadata.name}')"
echo c1_curl_pod_name $c1_curl_pod_name
```

### 4.2 确认服务调用效果

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

## 5 人工干预式服务融合

### 5.1 启用人工干预服务转化策略

```bash
kubectl get eurekaconnector -n fsm-system c1-eureka-to-c1-curl -o json | jq '.spec.syncToK8S.conversionStrategy.enable = true' | kubectl apply -f -
```

### 5.2 查看 eureka 上的服务

```bash
kubectl get eurekaconnector -n fsm-system c1-eureka-to-c1-curl -o jsonpath='{.status.catalogServices}' | jq
```

返回结果如下:

```jason
[
  {
    "service": "curl"
  },
  {
    "service": "httpbin"
  }
]
```

### 5.3 设置要导入的 eureka 上的服务

```bash
kubectl get eurekaconnector -n fsm-system c1-eureka-to-c1-curl -o json | jq '.spec.syncToK8S.conversionStrategy.serviceConversions += [{"service": "httpbin", "convertName": "httpbin-eureka"}]' | kubectl apply -f -
```

### 5.4 查看已经导入的服务

```bash
kubectl get service httpbin-eureka -n curl -o yaml
```

返回结果如下:

```yaml
apiVersion: v1
kind: Service
metadata:
  annotations:
    flomesh.io/cloud-endpoint-addr: eyJwb3J0cyI6eyIxNDAwMSI6Imh0dHAifSwiZW5kcG9pbnRzIjp7IjEwLjEwMS4wLjExIjp7InBvcnRzIjp7IjE0MDAxIjoiaHR0cCJ9LCJhZGRyZXNzIjoiMTAuMTAxLjAuMTEiLCJuYXRpdmUiOnsidmlhR2F0ZXdheU1vZGUiOiJmb3J3YXJkIn0sImxvY2FsIjp7fX0sIjEwLjEwMS4wLjEyIjp7InBvcnRzIjp7IjE0MDAxIjoiaHR0cCJ9LCJhZGRyZXNzIjoiMTAuMTAxLjAuMTIiLCJuYXRpdmUiOnsidmlhR2F0ZXdheU1vZGUiOiJmb3J3YXJkIn0sImxvY2FsIjp7fX19fQ==
    flomesh.io/cloud-endpoint-hash: "9683409494656067343"
    flomesh.io/cloud-service-inherited-from: httpbin
    flomesh.io/mesh-service-sync: eureka
    flomesh.io/mesh-service-sync-managed-by: 1b1433e9-ac28-451f-a09a-c8886dcece5b
  creationTimestamp: "2025-03-11T06:45:31Z"
  labels:
    fsm-connector-cloud-sourced-service: "true"
  name: httpbin-eureka
  namespace: curl
  resourceVersion: "1903"
  uid: 9ce216b5-e01d-49dd-9ab6-48a36237960b
spec:
  clusterIP: None
  clusterIPs:
  - None
  ipFamilies:
  - IPv4
  ipFamilyPolicy: SingleStack
  ports:
  - appProtocol: http
    name: http14001
    port: 14001
    protocol: TCP
    targetPort: 14001
  sessionAffinity: None
  type: ClusterIP
status:
  loadBalancer: {}
```

### 5.5 确认服务调用效果

**多次执行:**

```bash
kubectl exec -n curl $c1_curl_pod_name -c curl -- curl -s httpbin-eureka:14001
kubectl exec -n curl $c1_curl_pod_name -c curl -- curl -s httpbin-eureka:14001
```

**正确返回结果类似于:**

```bash
c1-httpbin-8497f8477b-lbrbv
c1-httpbin-8497f8477b-vhrfq
```

## 6 卸载 C1 集群

```bash
clusters="C1" make k3d-reset
```
