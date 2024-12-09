#!make

PORT_FORWARD ?= 14001:14001
WITH_MESH ?= false
WITH_PROXY ?=
COUNT ?= 1000

K3D_HOST_IP ?= 192.168.127.91

fsm_cluster_name ?= fsm
sidecar ?= NodeLevel
replicas ?= 1

CONSUL_VERSION ?= 1.15.4

.PHONY: k3d-up
k3d-up:
	./scripts/k3d-with-registry-multicluster$(WITH_PROXY).sh
	kubecm list

.PHONY: k3d-proxy-up
k3d-proxy-up:
	./scripts/k3d-with-registry-multicluster-with-proxy.sh
	kubecm list

.PHONY: k3d-reset
k3d-reset:
	./scripts/k3d-multicluster-cleanup.sh

.PHONY: deploy-fsm
deploy-fsm:
	fsm_cluster_name=$(fsm_cluster_name) sidecar=$(sidecar) scripts/deploy-fsm.sh

.PHONY: mount-debugfs
mount-debugfs:
	export INTERCEPTOR_POD=$$(kubectl get pods --selector app=fsm-interceptor -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl exec -n fsm-system "$$INTERCEPTOR_POD" -- mount -t debugfs debugfs /sys/kernel/debug

.PHONY: shell-node
shell-node:
	kubectl node-shell k3d-c1-server-0 -- sh

.PHONY: shell-xnet
shell-xnet:
	export XNETWORK_POD=$$(kubectl get pods --selector app=fsm-xnetwork -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl exec -it "$$XNETWORK_POD" -n fsm-system -c fsm-xnet -- bash

.PHONY: shell-xmgt
shell-xmgt:
	export XNETWORK_POD=$$(kubectl get pods --selector app=fsm-xnetwork -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl exec -it "$$XNETWORK_POD" -n fsm-system -c fsm-xmgt -- bash

.PHONY: restart-xnetwork
restart-xnetwork:
	kubectl rollout restart daemonset -n fsm-system fsm-xnetwork

.PHONY: tail-xmgt
tail-xmgt:
	export XNETWORK_POD=$$(kubectl get pods --selector app=fsm-xnetwork -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl logs "$$XNETWORK_POD" -n fsm-system -c fsm-xmgt -f

.PHONY: tail-xnet
tail-xnet:
	export XNETWORK_POD=$$(kubectl get pods --selector app=fsm-xnetwork -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl logs "$$XNETWORK_POD" -n fsm-system -c fsm-xnet -f

.PHONY: tail-xnet-kernel
tail-xnet-kernel:
	@export XNETWORK_POD=$$(kubectl get pods --selector app=fsm-xnetwork -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl exec "$$XNETWORK_POD" -n fsm-system -c fsm-xnet -- /usr/bin/mount -t debugfs debugfs /sys/kernel/debug >> /dev/null 2>&1 | true;\
	kubectl exec "$$XNETWORK_POD" -n fsm-system -c fsm-xnet -- /usr/bin/cat /sys/kernel/debug/tracing/trace_pipe | grep bpf_trace_printk

.PHONY: tail-xnet-kernel-reset
tail-xnet-kernel-reset:
	export XNETWORK_POD=$$(kubectl get pods --selector app=fsm-xnetwork -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	export CAT_PID=$$(kubectl exec "$$XNETWORK_POD" -n fsm-system -c fsm-xnet -- ps aux | grep cat | grep -v grep | awk '{print $$2}');\
	kubectl exec "$$XNETWORK_POD" -n fsm-system -c fsm-xnet -- kill -9 $$CAT_PID

.PHONY: consul-deploy
consul-deploy:
	kubectl apply -n default -f ./manifests/consul.$(CONSUL_VERSION).yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n default -l app=consul --timeout=180s
	until kubectl get service/consul --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

.PHONY: consul-reboot
consul-reboot:
	kubectl rollout restart deployment -n default consul

.PHONY: eureka-deploy
eureka-deploy:
	kubectl apply -n default -f ./manifests/eureka.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n default -l app=eureka --timeout=180s
	until kubectl get service/eureka --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

.PHONY: eureka-reboot
eureka-reboot:
	kubectl rollout restart deployment -n default eureka

.PHONY: nacos-deploy
nacos-deploy:
	kubectl apply -n default -f ./manifests/nacos.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n default -l app=nacos --timeout=180s
	until kubectl get service/nacos --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

.PHONY: nacos-auth-deploy
nacos-auth-deploy:
	kubectl apply -n default -f ./manifests/nacos-auth.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n default -l app=nacos --timeout=180s
	until kubectl get service/nacos --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

.PHONY: nacos-reboot
nacos-reboot:
	kubectl rollout restart deployment -n default nacos

.PHONY: zk-deploy
zk-deploy:
	kubectl apply -n default -f ./manifests/zookeeper.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n default -l app=zookeeper --timeout=180s

.PHONY: zk-reboot
zk-reboot:
	kubectl rollout restart deployment -n default zookeeper

.PHONY: consul-port-forward
consul-port-forward:
	export PORT_FORWARD=$(PORT_FORWARD);\
	export POD=$$(kubectl get pods --selector app=consul -n default --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl port-forward "$$POD" -n default "$$PORT_FORWARD" --address 0.0.0.0

.PHONY: eureka-port-forward
eureka-port-forward:
	export PORT_FORWARD=$(PORT_FORWARD);\
	export POD=$$(kubectl get pods --selector app=eureka -n default --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl port-forward "$$POD" -n default "$$PORT_FORWARD" --address 0.0.0.0

.PHONY: nacos-port-forward
nacos-port-forward:
	export PORT_FORWARD=$(PORT_FORWARD);\
	export POD=$$(kubectl get pods --selector app=nacos -n default --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl port-forward "$$POD" -n default "$$PORT_FORWARD" --address 0.0.0.0

.PHONY: zk-port-forward
zk-port-forward:
	export PORT_FORWARD=$(PORT_FORWARD);\
	export POD=$$(kubectl get pods --selector app=zookeeper -n default --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl port-forward "$$POD" -n default "2181:2181" --address 0.0.0.0 &
	export PORT_FORWARD=$(PORT_FORWARD);\
	export POD=$$(kubectl get pods --selector app=zookeeper -n default --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl port-forward "$$POD" -n default "8081:8081" --address 0.0.0.0 &

.PHONY: deploy-native-bookwarehouse
deploy-native-bookwarehouse: undeploy-native-bookwarehouse
	kubectl delete namespace bookwarehouse --ignore-not-found
	kubectl create namespace bookwarehouse
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add bookwarehouse; fi
	kubectl apply -n bookwarehouse -f ./manifests/native/bookwarehouse.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n bookwarehouse -l app=bookwarehouse --timeout=180s

.PHONY: undeploy-native-bookwarehouse
undeploy-native-bookwarehouse:
	kubectl delete -n bookwarehouse -f ./manifests/native/bookwarehouse.yaml --ignore-not-found

.PHONY: deploy-native-curl
deploy-native-curl: undeploy-native-curl
	kubectl delete namespace demo --ignore-not-found
	kubectl create namespace demo
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add demo; fi
	kubectl apply -n demo -f ./manifests/native/curl.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n demo -l app=curl --timeout=180s

.PHONY: undeploy-native-curl
undeploy-native-curl:
	kubectl delete -n demo -f ./manifests/native/curl.yaml --ignore-not-found

.PHONY: deploy-native-httpbin
deploy-native-httpbin: undeploy-native-httpbin
	kubectl delete namespace demo --ignore-not-found
	kubectl create namespace demo
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add demo; fi
	kubectl apply -n demo -f ./manifests/native/httpbin.yaml
	kubectl apply -n demo -f ./manifests/native/curl.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n demo -l app=httpbin --timeout=180s
	kubectl wait --all --for=condition=ready pod -n demo -l app=curl --timeout=180s

.PHONY: undeploy-native-httpbin
undeploy-native-httpbin:
	kubectl delete -n demo -f ./manifests/native/httpbin.yaml --ignore-not-found
	kubectl delete -n demo -f ./manifests/native/curl.yaml --ignore-not-found

.PHONY: deploy-native-httpbin-fault
deploy-native-httpbin-fault:
	kubectl apply -n demo -f ./manifests/native/httpbin-fault.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n demo -l app=httpbin --timeout=180s

.PHONY: deploy-consul-bookwarehouse
deploy-consul-bookwarehouse:
	kubectl delete namespace bookwarehouse --ignore-not-found
	kubectl create namespace bookwarehouse
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add bookwarehouse; fi
	kubectl apply -n bookwarehouse -f ./manifests/consul/bookwarehouse.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n bookwarehouse -l app=bookwarehouse --timeout=180s

.PHONY: deploy-consul-bookstore
deploy-consul-bookstore:
	kubectl delete namespace bookstore --ignore-not-found
	kubectl create namespace bookstore
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add bookstore; fi
	kubectl apply -n bookstore -f ./manifests/consul/bookstore.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n bookstore -l app=bookstore --timeout=180s

.PHONY: deploy-consul-bookbuyer
deploy-consul-bookbuyer:
	kubectl delete namespace bookbuyer --ignore-not-found
	kubectl create namespace bookbuyer
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add bookbuyer; fi
	kubectl apply -n bookbuyer -f ./manifests/consul/bookbuyer.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n bookbuyer -l app=bookbuyer --timeout=180s

.PHONY: deploy-consul-httpbin
deploy-consul-httpbin:
	kubectl delete namespace httpbin --ignore-not-found
	kubectl create namespace httpbin
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add httpbin; fi
	cluster=$(fsm_cluster_name) replicas=$(replicas) envsubst < ./manifests/consul/httpbin.yaml | kubectl apply -n httpbin -f -
	sleep 2
	kubectl wait --all --for=condition=ready pod -n httpbin -l app=httpbin --timeout=180s

.PHONY: deploy-consul-curl
deploy-consul-curl:
	kubectl delete namespace curl --ignore-not-found
	kubectl create namespace curl
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add curl; fi
	cluster=$(fsm_cluster_name) replicas=$(replicas) envsubst < ./manifests/consul/curl.yaml | kubectl apply -n curl -f -
	sleep 2
	kubectl wait --all --for=condition=ready pod -n curl -l app=curl --timeout=180s

.PHONY: deploy-eureka-bookwarehouse
deploy-eureka-bookwarehouse:
	kubectl delete namespace bookwarehouse --ignore-not-found
	kubectl create namespace bookwarehouse
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add bookwarehouse; fi
	kubectl apply -n bookwarehouse -f ./manifests/eureka/bookwarehouse.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n bookwarehouse -l app=bookwarehouse --timeout=180s

.PHONY: deploy-eureka-bookstore
deploy-eureka-bookstore:
	kubectl delete namespace bookstore --ignore-not-found
	kubectl create namespace bookstore
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add bookstore; fi
	kubectl apply -n bookstore -f ./manifests/eureka/bookstore.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n bookstore -l app=bookstore --timeout=180s

.PHONY: deploy-eureka-bookbuyer
deploy-eureka-bookbuyer:
	kubectl delete namespace bookbuyer --ignore-not-found
	kubectl create namespace bookbuyer
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add bookbuyer; fi
	kubectl apply -n bookbuyer -f ./manifests/eureka/bookbuyer.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n bookbuyer -l app=bookbuyer --timeout=180s

.PHONY: deploy-eureka-httpbin
deploy-eureka-httpbin:
	kubectl delete namespace httpbin --ignore-not-found
	kubectl create namespace httpbin
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add httpbin; fi
	cluster=$(fsm_cluster_name) replicas=$(replicas) envsubst < ./manifests/eureka/httpbin.yaml | kubectl apply -n httpbin -f -
	sleep 2
	kubectl wait --all --for=condition=ready pod -n httpbin -l app=httpbin --timeout=180s

.PHONY: deploy-eureka-curl
deploy-eureka-curl:
	kubectl delete namespace curl --ignore-not-found
	kubectl create namespace curl
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add curl; fi
	cluster=$(fsm_cluster_name) replicas=$(replicas) envsubst < ./manifests/eureka/curl.yaml | kubectl apply -n curl -f -
	sleep 2
	kubectl wait --all --for=condition=ready pod -n curl -l app=curl --timeout=180s

.PHONY: deploy-nacos-bookwarehouse
deploy-nacos-bookwarehouse:
	kubectl delete namespace bookwarehouse --ignore-not-found
	kubectl create namespace bookwarehouse
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add bookwarehouse; fi
	kubectl apply -n bookwarehouse -f ./manifests/nacos/bookwarehouse.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n bookwarehouse -l app=bookwarehouse --timeout=180s

.PHONY: deploy-nacos-bookstore
deploy-nacos-bookstore:
	kubectl delete namespace bookstore --ignore-not-found
	kubectl create namespace bookstore
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add bookstore; fi
	kubectl apply -n bookstore -f ./manifests/nacos/bookstore.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n bookstore -l app=bookstore --timeout=180s

.PHONY: deploy-nacos-bookbuyer
deploy-nacos-bookbuyer:
	kubectl delete namespace bookbuyer --ignore-not-found
	kubectl create namespace bookbuyer
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add bookbuyer; fi
	kubectl apply -n bookbuyer -f ./manifests/nacos/bookbuyer.yaml
	sleep 2
	kubectl wait --all --for=condition=ready pod -n bookbuyer -l app=bookbuyer --timeout=180s

.PHONY: deploy-nacos-httpbin
deploy-nacos-httpbin:
	kubectl delete namespace httpbin --ignore-not-found
	kubectl create namespace httpbin
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add httpbin; fi
	cluster=$(fsm_cluster_name) replicas=$(replicas) envsubst < ./manifests/nacos/httpbin.yaml | kubectl apply -n httpbin -f -
	sleep 2
	kubectl wait --all --for=condition=ready pod -n httpbin -l app=httpbin --timeout=180s

.PHONY: deploy-nacos-curl
deploy-nacos-curl:
	kubectl delete namespace curl --ignore-not-found
	kubectl create namespace curl
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add curl; fi
	cluster=$(fsm_cluster_name) replicas=$(replicas) envsubst < ./manifests/nacos/curl.yaml | kubectl apply -n curl -f -
	sleep 2
	kubectl wait --all --for=condition=ready pod -n curl -l app=curl --timeout=180s

.PHONY: deploy-zookeeper-nebula-grcp-server
deploy-zookeeper-nebula-grcp-server:
	kubectl delete namespace server --ignore-not-found
	kubectl create namespace server
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add server; fi
	cluster=$(fsm_cluster_name) replicas=$(replicas) envsubst < ./manifests/zookeeper/nebula/grcp.server.yaml | kubectl apply -n server -f -
	sleep 2
	kubectl wait --all --for=condition=ready pod -n server -l app=nebula-grpc-server --timeout=180s

.PHONY: deploy-zookeeper-nebula-grcp-client
deploy-zookeeper-nebula-grcp-client:
	kubectl delete namespace client --ignore-not-found
	kubectl create namespace client
	if [ "$(WITH_MESH)" = "true" ]; then fsm namespace add client; fi
	cluster=$(fsm_cluster_name) replicas=$(replicas) envsubst < ./manifests/zookeeper/nebula/grcp.client.yaml | kubectl apply -n client -f -
	sleep 2
	kubectl wait --all --for=condition=ready pod -n client -l app=nebula-grpc-client --timeout=180s

port-forward-fsm-repo:
	export PORT_FORWARD=$(PORT_FORWARD);\
	export POD=$$(kubectl get pods --selector app=fsm-controller -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl port-forward "$$POD" -n fsm-system "$$PORT_FORWARD" --address 0.0.0.0

.PHONY: bookbuyer-port-forward
bookbuyer-port-forward:
	export PORT_FORWARD=$(PORT_FORWARD);\
	export POD=$$(kubectl get pods --selector app=bookbuyer -n bookbuyer --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl port-forward "$$POD" -n bookbuyer "$$PORT_FORWARD" --address 0.0.0.0

.PHONY: up-scenarios-2.1
up-scenarios-2.1:
	./scripts/scenarios.2.1.sh

.PHONY: down-scenarios-2.1
down-scenarios-2.1:
	export clusters="C1";make k3d-reset

.PHONY: up-scenarios-2.2
up-scenarios-2.2:
	./scripts/scenarios.2.2.sh

.PHONY: down-scenarios-2.2
down-scenarios-2.2:
	export clusters="C1";make k3d-reset

.PHONY: up-scenarios-2.6
up-scenarios-2.6:
	./scripts/scenarios.2.6.sh

.PHONY: down-scenarios-2.6
down-scenarios-2.6:
	export clusters="C1";make k3d-reset

.PHONY: up-scenarios-2.7
up-scenarios-2.7:
	./scripts/scenarios.2.7.sh

.PHONY: down-scenarios-2.7
down-scenarios-2.7:
	export clusters="C1 C2 C3";make k3d-reset

.PHONY: up-scenarios-2.8
up-scenarios-2.8:
	./scripts/scenarios.2.8.sh

.PHONY: down-scenarios-2.8
down-scenarios-2.8:
	export clusters="C1 C2 C3";make k3d-reset

.PHONY: up-scenarios-2.9
up-scenarios-2.9:
	./scripts/scenarios.2.9.sh

.PHONY: down-scenarios-2.9
down-scenarios-2.9:
	export clusters="C1 C2 C3";make k3d-reset

.PHONY: up-scenarios-2.10
up-scenarios-2.10:
	./scripts/scenarios.2.10.sh

.PHONY: down-scenarios-2.10
down-scenarios-2.10:
	export clusters="C1";make k3d-reset

.PHONY: up-scenarios-2.11
up-scenarios-2.11:
	./scripts/scenarios.2.11.sh

.PHONY: down-scenarios-2.11
down-scenarios-2.11:
	export clusters="C1 C2 C3";make k3d-reset
