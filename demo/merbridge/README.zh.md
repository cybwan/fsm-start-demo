

# FSM&Merbridge集成测试

## 1.部署k8s环境

### 1.1 部署环境准备

- [ ] 部署 3 个 **ubuntu 22.04/20.04** 的虚机，一个作为 master，两个作为 node

- [ ] 主机名分别设置为 master，node1，node2

- [ ] 修改/etc/hosts，使其相互间可以通过主机名互通

- [ ] 更新系统软件包: 

  ```bash
  sudo apt -y update && sudo apt -y upgrade
  ```

- [ ] root身份执行后续部署指令

### 1.2 各虚拟机上部署容器环境

```bash
curl -L https://raw.githubusercontent.com/cybwan/fsm-scripts/main/scripts/install-k8s-node-init.sh -O
chmod u+x install-k8s-node-init.sh

system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
./install-k8s-node-init.sh ${arch} ${system}
```

### 1.3 各虚拟机上部署 k8s 工具

```bash
curl -L https://raw.githubusercontent.com/cybwan/fsm-scripts/main/scripts/install-k8s-node-init-tools.sh -O
chmod u+x install-k8s-node-init-tools.sh

system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
./install-k8s-node-init-tools.sh ${arch} ${system}

source ~/.bashrc 
```

### 1.4 Master节点启动 k8s 相关服务

```bash
curl -L https://raw.githubusercontent.com/cybwan/fsm-scripts/main/scripts/install-k8s-node-master-start.sh -O
chmod u+x install-k8s-node-master-start.sh

#调整为你的 master 的 ip 地址
MASTER_IP=192.168.127.80
#使用 flannel 网络插件
CNI=flannel
./install-k8s-node-master-start.sh ${MASTER_IP} ${CNI}
#耐心等待...
```

### 1.5 Node1&2节点启动 k8s 相关服务

```bash
curl -L https://raw.githubusercontent.com/cybwan/fsm-scripts/main/scripts/install-k8s-node-worker-join.sh -O
chmod u+x install-k8s-node-worker-join.sh

#调整为你的 master 的 ip 地址
MASTER_IP=192.168.127.80
#安装过程会提示输入 master 的 root 的密码
./install-k8s-node-worker-join.sh ${MASTER_IP}
```

### 1.6 Master节点查看 k8s 相关服务的启动状态

```bash
kubectl get pods -A -o wide
```

## 2. 部署 fsm 服务

### 2.1 下载并安装 fsm 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.0.0
curl -L https://github.com/flomesh-io/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/fsm version
cp ./${system}-${arch}/fsm /usr/local/bin/
```

### 2.2 安装 fsm

```bash
export fsm_namespace=fsm-system 
export fsm_mesh_name=fsm 

fsm install \
    --mesh-name "$fsm_mesh_name" \
    --fsm-namespace "$fsm_namespace" \
    --set=fsm.image.registry=flomesh \
    --set=fsm.image.tag=1.0.0 \
    --set=fsm.certificateProvider.kind=tresor \
    --set=fsm.image.pullPolicy=Always \
    --set=fsm.enablePermissiveTrafficPolicy=true \
    --set=fsm.controllerLogLevel=warn \
    --timeout=900s
```

如果部署 fsm,指令参考:

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.0.0
curl -L https://github.com/openservicemesh/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/fsm version
cp ./${system}-${arch}/fsm /usr/local/bin/

export fsm_namespace=fsm-system 
export fsm_mesh_name=fsm 

fsm install \
    --mesh-name "$fsm_mesh_name" \
    --fsm-namespace "$fsm_namespace" \
    --set=fsm.image.registry=openservicemesh \
    --set=fsm.image.tag=v1.2.3 \
    --set=fsm.certificateProvider.kind=tresor \
    --set=fsm.image.pullPolicy=Always \
    --set=fsm.enablePermissiveTrafficPolicy=true \
    --set=fsm.controllerLogLevel=warn \
    --verbose \
    --timeout=900s
```

## 3. 部署 Merbridge 服务

```
curl -L https://raw.githubusercontent.com/merbridge/merbridge/main/deploy/all-in-one-fsm.yaml -O
sed -i 's/--cni-mode=false/--cni-mode=true/g' all-in-one-fsm.yaml
sed -i '/--cni-mode=true/a\\t\t- --debug=true' all-in-one-fsm.yaml
sed -i 's/\t/    /g' all-in-one-fsm.yaml
kubectl apply -f all-in-one-fsm.yaml

sleep 5s
kubectl wait --for=condition=ready pod -n fsm-system -l app=merbridge --field-selector spec.nodeName==master --timeout=1800s
kubectl wait --for=condition=ready pod -n fsm-system -l app=merbridge --field-selector spec.nodeName==node1 --timeout=1800s
kubectl wait --for=condition=ready pod -n fsm-system -l app=merbridge --field-selector spec.nodeName==node2 --timeout=1800s
```

## 4. Merbridge 替代 iptables 测试

### 4.1 部署业务 POD

```bash
#模拟业务服务
kubectl create namespace demo
fsm namespace add demo
kubectl apply -n demo -f https://raw.githubusercontent.com/istio/istio/master/samples/sleep/sleep.yaml
kubectl apply -n demo -f https://raw.githubusercontent.com/istio/istio/master/samples/helloworld/helloworld.yaml

#让 Pod 分布到不同的 node 上
kubectl patch deployments sleep -n demo -p '{"spec":{"template":{"spec":{"nodeName":"node1"}}}}'
kubectl patch deployments helloworld-v1 -n demo -p '{"spec":{"template":{"spec":{"nodeName":"node1"}}}}'
kubectl patch deployments helloworld-v2 -n demo -p '{"spec":{"template":{"spec":{"nodeName":"node2"}}}}'

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n demo -l app=sleep --timeout=180s
kubectl wait --for=condition=ready pod -n demo -l app=helloworld -l version=v1 --timeout=180s
kubectl wait --for=condition=ready pod -n demo -l app=helloworld -l version=v2 --timeout=180s
```

### 4.2 场景测试一

#### 4.2.1 在 node1&2 上监测内核日志

```bash
cat /sys/kernel/debug/tracing/trace_pipe|grep bpf_trace_printk|grep -E "rewritten|redirect"
```

#### 4.2.2 测试指令

多次执行:

```bash
kubectl exec $(kubectl get po -l app=sleep -n demo -o=jsonpath='{..metadata.name}') -n demo -c sleep -- curl -s helloworld:5000/hello
```

#### 4.2.3 测试结果

正确返回结果类似于:

```bash
Hello version: v1, instance: helloworld-v1-5d46f78b4c-hghcj
Hello version: v2, instance: helloworld-v2-6b56769f9d-stwrj
```

