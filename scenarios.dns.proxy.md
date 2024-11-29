# 场景 DNS 服务测试

## 1 部署 k3d 集群

```bash
export clusters="C1"
make k3d-up
```

## 2 部署服务

```bash
kubecm switch k3d-C1
```

### 2.1 部署 FSM Mesh

```bash
fsm_cluster_name=C1 make deploy-fsm
```

### 2.2 部署 业务 服务

```bash
#https://www.cnblogs.com/sunnydou/p/15087728.html

kubectl create namespace e1995-mesh
fsm namespace add e1995-mesh

kubectl apply -n e1995-mesh -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: curl
spec:
  replicas: 1
  selector:
    matchLabels:
      app: curl
  template:
    metadata:
      labels:
        app: curl
    spec:
      containers:
      - name: centos8
        image: centos:centos8
        imagePullPolicy: IfNotPresent
        command: [ "sleep", "365d" ]
      - name: centos7
        image: centos:centos7
        imagePullPolicy: IfNotPresent
        command: [ "sleep", "365d" ]
      - name: ubuntu22
        image: localhost:5000/cybwan/ubuntu:22.04
        imagePullPolicy: IfNotPresent
        command: [ "sleep", "365d" ]
EOF
```

## 4 卸载 k3d 集群

```bash
export clusters="C1"
make k3d-reset
```
