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
WITH_MESH=false replicas=2 make deploy-hostname-httpbin
```

### 3.2 配置 E4LB 策略

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
hi, I am httpbin from host: httpbin-849db69c94-f9x9k at node: k3d-c1-server-0 by pipy!
hi, I am httpbin from host: httpbin-849db69c94-xf2gf at node: k3d-c1-server-0 by pipy!
```

调用效果是分别从两个服务实例返回.

## 4 卸载 K8S 集群

```bash
docker stop e4lb-client
clusters="C1" make k3d-reset
```
