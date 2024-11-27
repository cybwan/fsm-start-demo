# 场景一 单服务单副本

## 1 部署 C1 C2 C3 三个集群

#bash
export clusters="C1 C2 C3"
make k3d-up
#

## 2 部署服务

### 2.1 C1集群

#bash
kubecm switch k3d-C1
#

#### 2.1.1 部署 ZTM HUB 服务

#bash
make ztm-svc-deploy

export ztm_hub_external_ip="$(kubectl get svc -n default --field-selector metadata.name=ztm-hub -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')"
echo ztm_hub_external_ip $ztm_hub_external_ip

names=$ztm_hub_external_ip make ztm-hub-deploy

export ztm_hub_pod="$(kubectl get pod -n default --selector app=ztm-hub -o jsonpath='{.items[0].metadata.name}')"
echo ztm_hub_pod $ztm_hub_pod

kubectl cp -n default ${ztm_hub_pod}:fsm.perm.json /tmp/fsm.perm.json
#

### 2.2 C2集群

#bash
kubecm switch k3d-C2
#

#### 2.2.1 部署 httpbin 服务

#bash
replicas=1 cluster=C2 make httpbin-deploy

export c2_httpbin_1_pod_ip="$(kubectl get pod -n demo --selector app=httpbin -o jsonpath='{.items[0].status.podIP}')"
echo c2_httpbin_1_pod_ip $c2_httpbin_1_pod_ip

export c2_httpbin_svc_port="$(kubectl get -n demo svc httpbin -o jsonpath='{.spec.ports[0].port}')"
echo c2_httpbin_svc_port $c2_httpbin_svc_port

export c2_httpbin_svc_target_port="$(kubectl get -n demo svc httpbin -o jsonpath='{.spec.ports[0].targetPort}')"
echo c2_httpbin_svc_target_port $c2_httpbin_svc_target_port

make curl-deploy

export c2_curl_pod="$(kubectl get pod -n demo --selector app=curl -o jsonpath='{.items[0].metadata.name}')"
echo c2_curl_pod $c2_curl_pod
#

#### 2.2.3 部署 FSM Mesh

#bash
fsm_cluster_name=C2 make deploy-fsm
#

#### 2.2.4 部署 ZTM Agent

#bash
kubectl apply  -f - <<EOF
kind: Agent
apiVersion: ztm.flomesh.io/v1alpha1
metadata:
  name: c2-agent
spec:
  permit:
    bootstraps: $(cat /tmp/fsm.perm.json | jq .bootstraps)
    ca: $(cat /tmp/fsm.perm.json | jq .ca)
    agent:
      privateKey: $(cat /tmp/fsm.perm.json | jq .agent.privateKey)
      certificate: $(cat /tmp/fsm.perm.json | jq .agent.certificate)
  joinMeshes:
  - meshName: k8s
EOF

sleep 2
kubectl wait --all --for=condition=ready pod -n fsm-system -l app=fsm-ztmagent-c2-agent --timeout=180s
#

#### 2.2.5 导出服务

#bash
kubectl apply -n demo -f - <<EOF
apiVersion: multicluster.flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  name: httpbin
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 80
      path: "/"
      pathType: Prefix
EOF
#

### 2.3 C3集群

#bash
kubecm switch k3d-C3
#

#### 2.3.1 部署 FSM Mesh

#bash
fsm_cluster_name=C3 make deploy-fsm
#

#### 2.3.2 部署 curl 服务

#bash
WITH_MESH=true make curl-deploy

export c3_curl_pod="$(kubectl get pod -n demo --selector app=curl -o jsonpath='{.items[0].metadata.name}')"
echo c3_curl_pod $c3_curl_pod
#

#### 2.3.3 部署 httpbin 服务

#bash
WITH_MESH=true replicas=1 cluster=C3 make httpbin-deploy

export c3_httpbin_svc_port="$(kubectl get -n demo svc httpbin -o jsonpath='{.spec.ports[0].port}')"
echo c3_httpbin_svc_port $c3_httpbin_svc_port
#

#### 2.3.5 部署 ZTM Agent

#bash
kubectl apply  -f - <<EOF
kind: Agent
apiVersion: ztm.flomesh.io/v1alpha1
metadata:
  name: c3-agent
spec:
  permit:
    bootstraps: $(cat /tmp/fsm.perm.json | jq .bootstraps)
    ca: $(cat /tmp/fsm.perm.json | jq .ca)
    agent:
      privateKey: $(cat /tmp/fsm.perm.json | jq .agent.privateKey)
      certificate: $(cat /tmp/fsm.perm.json | jq .agent.certificate)
  joinMeshes:
  - meshName: k8s
EOF

sleep 2
kubectl wait --all --for=condition=ready pod -n fsm-system -l app=fsm-ztmagent-c3-agent --timeout=180s
#

#### 2.3.6 设置多集群负载均衡策略

#bash
cat <<EOF | kubectl apply -f -
apiVersion: multicluster.flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: demo
  name: httpbin
spec:
  lbType: ActiveActive
EOF
#

echo
echo ztm_hub_external_ip $ztm_hub_external_ip
echo ztm_hub_pod $ztm_hub_pod

echo
echo c2_httpbin_1_pod_ip $c2_httpbin_1_pod_ip
echo c2_httpbin_svc_port $c2_httpbin_svc_port
echo c2_httpbin_svc_target_port $c2_httpbin_svc_target_port
echo c2_curl_pod $c2_curl_pod

echo
echo c3_curl_pod $c3_curl_pod
echo c3_httpbin_svc_port $c3_httpbin_svc_port

echo

#### 2.3.6 测试 httpbin 服务
#bash
echo kubectl exec $c3_curl_pod -n demo -c curl -- curl -s http://httpbin:$c3_httpbin_svc_port
#