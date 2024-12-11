

# FSM Connector 跨集群混合架构微服务融合测试

## 下载并安装 fsm 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.4.2
curl -L https://github.com/flomesh-io/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/fsm version
cp ./${system}-${arch}/fsm /usr/local/bin/
```

## 下载 Demo 资源

```bash
git clone https://github.com/cybwan/fsm-start-demo.git -b connector
cd fsm-start-demo
```

## 场景一: [Consul 跨集群微服务融合](scenarios.1.1.md)

### **调用流程**

```html
[c3 consul bookbuyer]
-(sidecar)->
[c3 fgw egress]
-->
[c2 fgw ingress]
-(sidecar)->
[c2 consul bookstore]
-(sidecar)->
[c2 fgw egress]
-->
[c1 fgw ingress]
-(sidecar)->
[c1 consul bookwarehouse]
```

## 场景二: [Consul & K8S 跨集群混合架构微服务融合](scenarios.2.md)(多级 fgw)

### **调用流程**

```html
[c3 consul bookbuyer]
-(sidecar)->
[c3 fgw egress]
-->
[c2 fgw ingress]
-(sidecar)->
[c2 consul bookstore]
-(sidecar)->
[c2 fgw egress]
-->
[c1 fgw ingress]
-(sidecar)->
[c1 native bookwarehouse]
```

## 场景三: [Consul & Eureka & Nacos 跨集群混合架构微服务融合](scenarios.3.md)

### **调用流程**

```html
[c3 nacos bookbuyer]
-(sidecar)->
[c3 fgw egress]
-->
[c2 fgw ingress]
-(sidecar)->
[c2 eureka bookstore]
-(sidecar)->
[c2 fgw egress]
-->
[c1 fgw ingress]
-(sidecar)->
[c1 consul bookwarehouse]
```

## 场景四: [Consul & K8S 跨集群混合架构微服务融合](scenarios.4.md)(禁用多级 fgw)

### **调用流程**

```html
[c3 consul bookbuyer]
-(sidecar)->
-->
[c2 fgw ingress]
-(sidecar)->
[c2 consul bookstore]
-(sidecar)->
-->
[c1 fgw ingress]
-(sidecar)->
[c1 native bookwarehouse]
```

## 场景五: [Nacos 微服务整合](scenarios.5.md)

### **调用流程**

```html
[c1 nacos curl]
-(c1 nacos curl sidecar)->
-(c1 nacos httpbin sidecar)->
[c1 consul httpbin]
```

## 场景六: [Nacos 多集群HA微服务融合](scenarios.6.md)

## 场景九: [Eureka 跨集群微服务融合压力测试](scenarios.9.md)

## 场景十: [Consul 跨集群微服务多网关Forward模式](scenarios.a.md)

## 场景十一: [Consul 跨集群微服务单网关Forward模式](scenarios.b.md)

## 场景十二: [Consul 跨集群微服务多网关Proxy模式](scenarios.c.md)

## 场景十三: [Consul 跨集群微服务单网关Proxy模式](scenarios.d.md)

## 场景十四: [Consul 跨集群微服务融合HA测试](scenarios.e.md)