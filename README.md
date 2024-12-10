# MESH2 业务场景测试

## 1 部署要求

### 1.1 安装k3d 

**最低 v5.5.0 版本**

```bash
if [ ! -f /usr/local/bin/k3d ]; then
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi
```

### 1.2 安装 kubecm

```bash
arch=$(arch | sed s/aarch64/arm64/)
version=v0.32.0
if [ ! -f /usr/local/bin/kubecm ]; then
  curl -Lo kubecm.tar.gz https://github.com/sunny0826/kubecm/releases/download/${version}/kubecm_${version}_Linux_${arch}.tar.gz
  tar -zxvf kubecm.tar.gz kubecm
  chmod a+x kubecm
  mv kubecm /usr/local/bin/kubecm
  rm -rf kubecm.tar.gz
fi
```

### 1.3 下载并安装 fsm 命令行工具

```bash
https://github.com/cybwan/fsm/releases/tag/v1.5.0-alpha.4
```

### 1.4 设置环境变量

```bash
export CTR_REGISTRY=cybwan
export CTR_TAG=1.5.0-alpha.4
```

### 1.5 下载 DEMO 工程

```bash
git https://github.com/cybwan/fsm-start-demo.git -b mesh2
cd fsm-start-demo
```

## 2 业务场景测试

### 2.1    场景 [HTTP 业务测试](scenarios.2.1.md)

### 2.2   场景 [DNS 业务测试](scenarios.2.2.md)

### 2.3   场景 [灰度测试](scenarios.3.md) 待续

### 2.4   场景 [限流测试](scenarios.4.md) 待续

### 2.5   场景 [熔断测试](scenarios.5.md) 待续

### 2.6   场景 [Nacos 单集群微服务融合测试](scenarios.2.6.md)

### 2.7   场景 [Consul 多集群微服务融合测试](scenarios.2.7.md)

### 2.8   场景 [Consul & Eureka & Nacos 混合架构微服务融合测试](scenarios.2.8.md)

### 2.9   场景 [Consul 多集群微服务高可用测试](scenarios.2.9.md) 待实现

### 2.10 场景 [Nebula-GRPC 单集群微服务融合测试](scenarios.2.10.md)

### 2.11 场景 [Nebula-GRPC 多集群高可用微服务融合测试](scenarios.2.11.md)