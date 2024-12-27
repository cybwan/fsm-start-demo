# 场景 虚拟机微服务融合测试

## 1 部署 K8S 集群

```bash
clusters="C1" make k3d-up
```

## 2 部署服务

```bash
kubecm switch k3d-C1
```

### 2.1 部署 FSM Mesh

```bash
fsm_cluster_name=C1 sidecar=PodLevel make deploy-fsm
```

### 2.2 部署 VM 服务

```bash
kubectl create namespace derive-vm1
fsm namespace add derive-vm1

kubectl apply -n derive-vm1 -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vm168
---
kind: VirtualMachine
apiVersion: machine.flomesh.io/v1alpha1
metadata:
  name: vm168
spec:
  serviceAccountName: vm168
  machineIP: 10.69.17.168
EOF
```

## 4 卸载 K8S 集群

```bash
clusters="C1" make k3d-reset
```
