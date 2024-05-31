# 常用指令

## 查看 connector

```
connector_type=nacos
sudo kubectl get ${connector_type}connector -A
```

## 查看 connector 的yaml

```bash
connector_type=nacos
connector_name=cluster2-to-nacos1
sudo kubectl get ${connector_type}connector ${connector_name} -o yaml
```

## 查看 connector 的 deployment 的yaml

```bash
connector_type=nacos
connector_name=cluster2-to-nacos1
sudo kubectl get deploy -n fsm-system fsm-connector-${connector_type}-${connector_name} -o yaml
```

## 编辑 connector 的 deployment

```bash
connector_type=nacos
connector_name=cluster2-to-nacos1
sudo kubectl edit deploy -n fsm-system fsm-connector-${connector_type}-${connector_name}
```

## 查看 connector 的 pod 的日志

```bash
connector_type=nacos
connector_name=cluster2-to-nacos1
connector_pod=$(sudo kubectl get pod -n fsm-system -l app=fsm-connector-${connector_type}-${connector_name} -o jsonpath='{.items[0].metadata.name}')
sudo kubectl logs -n fsm-system ${connector_pod} -f
```

## 查看 connector 的 pod 的yaml

```bash
connector_type=nacos
connector_name=cluster2-to-nacos1
connector_pod=$(sudo kubectl get pod -n fsm-system -l app=fsm-connector-${connector_type}-${connector_name} -o jsonpath='{.items[0].metadata.name}')
sudo kubectl get pod -n fsm-system ${connector_pod} -o yaml
```

