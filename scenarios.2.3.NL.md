# 场景 E4LB 业务测试

## 1 部署 K8S 集群

```bash
clusters="C1" agents=2 make k3d-up
kubecm switch k3d-C1
```

## 2 部署网格服务

```bash
fsm_cluster_name=C1 sidecar=NodeLevel k3s=true mesh=false e4lb=true make deploy-fsm
```

## 3 E4LB 业务测试

### 3.1 部署模拟业务服务

```bash
WITH_MESH=false replicas=3 make deploy-hostname-httpbin
```

### 3.2 配置 EIP

**有如下两种方式配置 EIP:**

#### 3.2.1 配置 Annotations

##### 3.2.1.1 配置 Node E4LB Annotations

```bash
kubectl patch node k3d-c1-server-0 --type=json -p='[{"op": "add", "path": "/metadata/annotations/flb.flomesh.io~1enabled", "value": "true"}]' 
```

**注:**

- **如果没有 node 配置这个annotation, 则从所有 node 中选择一个**

- **如果多个 node 配置这个annotation, 则从多个 node 中选择一个**

##### 3.2.1.2 配置 Service EIP Annotations

```bash
kubectl patch service -n demo httpbin --type=json -p='[{"op": "add", "path": "/metadata/annotations/flb.flomesh.io~1enabled", "value": "true"}]' 
kubectl patch service -n demo httpbin --type=json -p='[{"op": "add", "path": "/metadata/annotations/flb.flomesh.io~1desired-ip", "value": "172.22.0.188"}]' 
```

#### 3.2.2 配置 E4LB 策略

```bash
kubectl apply -n demo -f - <<EOF
kind: EIPAdvertisement
apiVersion: xnetwork.flomesh.io/v1alpha1
metadata:
  name: demo
spec:
  service: 
    name: httpbin
  eip: 172.22.0.188
  nodes:
  - k3d-c1-server-0
EOF
```

**注:**

- **如果没有设置 nodes,则遵循 3.2.1.1 的规则**

### 3.3 部署模拟外部客户端

```bash
docker run -d --network fsm --rm --name e4lb-client -t cybwan/curl:latest sleep 1h
```

### 3.4 服务调用效果

多次执行:

```bash
docker exec e4lb-client /usr/bin/curl -s 172.22.0.188:80
```

返回结果如下:

```bash
hi, I am httpbin from host: httpbin-66d5b5b879-5nfc5 at node: k3d-c1-server-0 by pipy!
hi, I am httpbin from host: httpbin-66d5b5b879-jb6mj at node: k3d-c1-agent-1 by pipy!
hi, I am httpbin from host: httpbin-66d5b5b879-jb6mj at node: k3d-c1-agent-1 by pipy!
```

调用效果是分别从三个服务实例返回.

## 4 卸载 K8S 集群

```bash
docker stop e4lb-client
clusters="C1" make k3d-reset
```
