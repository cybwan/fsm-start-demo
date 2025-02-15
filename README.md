# MESH 业务场景测试

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
https://github.com/cybwan/fsm/releases/tag/v1.5.0-alpha.15
```

### 1.4 设置环境变量

```bash
export CTR_REGISTRY=cybwan
export CTR_TAG=1.5.0-alpha.15
export K3D_HOST_IP=192.168.127.91 #调整为你的本地IP
```

### 1.5 下载 DEMO 工程

```bash
git clone https://github.com/cybwan/fsm-start-demo.git -b mesh2
cd fsm-start-demo
```

## 2 基础业务场景测试

#### 2.1   HTTP 业务测试 [Node Level](scenarios.2.1.md) ✓

#### 2.2   DNS 业务测试 [Node Level](scenarios.2.2.NL.md) ✓

#### 2.3   E4LB业务测试 [Node Level](scenarios.2.3.NL.md) ✓

#### 2.4   灰度测试 待续

#### 2.5   限流测试 待续

#### 2.6   熔断测试 待续

#### 2.7   慢启动预热策略测试 [Pod Level](scenarios.2.7.md) ✓

#### 2.8   SmartDNS业务测试 [Node Level Flannel](scenarios.2.8.1.NL.md) ✓ [Node Level Calico vxlan](scenarios.2.8.2.NL.md) ✓

## 3 融合业务场景测试

### 3.1 单集群微服务融合测试

#### 3.1.1 Consul HTTP 单集群微服务融合测试 [Pod Level](scenarios.3.1.1.PL.md) ✓ | [Node Level](scenarios.3.1.1.NL.md) ✓

#### 3.1.2 Eureka HTTP 单集群微服务融合测试 [Pod Level](scenarios.3.1.2.PL.md) ✓ | [Node Level](scenarios.3.1.2.NL.md) ✓

#### 3.1.3 Nacos HTTP 单集群微服务融合测试 [Pod Level](scenarios.3.1.3.PL.md) ✓ | [Node Level](scenarios.3.1.3.NL.md) ✓

#### 3.1.4 Nebula gRPC 单集群微服务融合测试 [Pod Level](scenarios.3.1.4.PL.md) ✓ | [Node Level](scenarios.3.1.4.NL.md) ✓

### 3.2 多集群微服务融合测试

#### 3.2.1 Consul HTTP 多集群微服务融合测试 [Pod Level](scenarios.3.2.1.PL.md) ✓ | [Node Level](scenarios.3.2.1.NL.md) ✓

#### 3.2.2 Eureka HTTP 多集群微服务融合测试 [Pod Level](scenarios.3.2.2.PL.md) ✓ | [Node Level](scenarios.3.2.2.NL.md) ✓

#### 3.2.3 Nacos HTTP 多集群微服务融合测试 [Pod Level](scenarios.3.2.3.PL.md) ✓ | [Node Level](scenarios.3.2.3.NL.md) ✓

#### 3.2.4 Nebula gRPC 多集群微服务融合测试 [Pod Level](scenarios.3.2.4.PL.md) ✓ | [Node Level](scenarios.3.2.4.NL.md) ✓

### 3.3 混合架构微服务融合测试

#### 3.3.1 Consul & Eureka & Nacos HTTP 混合架构微服务融合测试 [Pod Level](scenarios.3.3.1.PL.md) ✓ | [Node Level](scenarios.3.3.1.NL.md) ✓

## 3.4 纳管虚机多集群微服务融合测试

#### 3.4.1 Consul HTTP 多集群微服务融合测试 [Pod Level](scenarios.3.4.1.PL.md) | [Node Level](scenarios.3.4.1.NL.md)

#### 3.4.2 Eureka HTTP 多集群微服务融合测试 [Pod Level](scenarios.3.4.2.PL.md) | [Node Level](scenarios.3.4.2.NL.md)

#### 3.4.3 Nacos HTTP 多集群微服务融合测试 [Pod Level](scenarios.3.4.3.PL.md) | [Node Level](scenarios.3.4.3.NL.md)

#### 3.4.4 Nebula gRPC 多集群微服务融合测试 [Pod Level](scenarios.3.4.4.PL.md) | [Node Level](scenarios.3.4.4.NL.md)