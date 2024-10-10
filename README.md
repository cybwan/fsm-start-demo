# 场景 Consul 跨集群微服务融合HA测试

## 1 部署 C1 C2 C3 三个集群

```bash
export clusters="C1"
make k3d-up
```

## 2 部署服务

### 2.1 C1集群

```bash
kubecm switch k3d-C1
```

#### 2.1.1 部署 FSM Mesh

```bash
fsm_cluster_name=C1 make deploy-fsm

make rebuild-fsm-interceptor restart-fsm-interceptor
```

#### 2.1.2 启用按请求负载均衡策略

```bash
#模拟业务服务
kubectl create namespace ebpf
fsm namespace add ebpf
kubectl apply -n ebpf -f manifests/curl.yaml
kubectl apply -n ebpf -f manifests/pipy-ok.yaml

sleep 3

kubectl wait --all --for=condition=ready pod -n ebpf -l app=curl --timeout=180s
kubectl wait --all --for=condition=ready pod -n ebpf -l app=pipy-ok --timeout=180s

curl_client="$(kubectl get pod -n ebpf -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_client} -n ebpf -c curl -- curl -s pipy-ok:8080

mount -t debugfs debugfs /sys/kernel/debug
cat /sys/kernel/debug/tracing/trace_pipe|grep bpf_trace_printk
```

## 6 卸载 C1 C2 C3 三个集群

```bash
export clusters="C1"
make k3d-reset
```



```json
{"level":"error","component":"cni-plugin","time":"2024-10-10T05:20:10Z","file":"plugin.go:183","message":"fsm-cni cmdDelete failed to parse config {\"cniVersion\":\"0.3.1\",\"kubernetes\":{\"kubeconfig\":\"/etc/cni/net.d/ZZZ-fsm-cni-kubeconfig\"},\"name\":\"cbr0\",\"type\":\"fsm-cni\"} <nil>"}
```

