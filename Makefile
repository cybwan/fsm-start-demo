#!make

PORT_FORWARD ?= 14001:14001
WITH_MESH ?= false
COUNT ?= 1000

fsm_cluster_name ?= fsm
replicas ?= 1

.PHONY: k3d-up
k3d-up:
	./scripts/k3d-with-registry-multicluster.sh
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
	$fsm_cluster_name=$(fsm_cluster_name) scripts/deploy-fsm.sh

CONSUL_VERSION ?= 1.15.4

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

port-forward-fsm-repo:
	export PORT_FORWARD=$(PORT_FORWARD);\
	export POD=$$(kubectl get pods --selector app=fsm-controller -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl port-forward "$$POD" -n fsm-system "$$PORT_FORWARD" --address 0.0.0.0

.PHONY: bookbuyer-port-forward
bookbuyer-port-forward:
	export PORT_FORWARD=$(PORT_FORWARD);\
	export POD=$$(kubectl get pods --selector app=bookbuyer -n bookbuyer --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl port-forward "$$POD" -n bookbuyer "$$PORT_FORWARD" --address 0.0.0.0

.PHONY: curl-port-forward
curl-port-forward:
	export PORT_FORWARD=$(PORT_FORWARD);\
	export POD=$$(kubectl get pods --selector app=curl -n curl --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl port-forward "$$POD" -n curl "$$PORT_FORWARD" --address 0.0.0.0

.PHONY: tail-fgw-sidecar
tail-fgw-sidecar:
	export POD=$$(kubectl get pods --selector app=fsm-gateway -n fsm-system --no-headers | grep 'Running' | awk 'NR==1{print $$1}');\
	kubectl logs "$$POD" -n fsm-system -c gateway -f

.PHONY: batch-create-eureka-services
batch-create-eureka-services:
	./scripts/eurekacli --action create --count $(COUNT)

.PHONY: batch-delete-eureka-services
batch-delete-eureka-services:
	./scripts/eurekacli --action delete --count $(COUNT)

.PHONY: batch-create-eureka-multi-ports-services
batch-create-eureka-multi-ports-services:
	./scripts/eureka-multi-ports-cli --action create --count $(COUNT)

.PHONY: batch-delete-eureka-multi-ports-services
batch-delete-eureka-multi-ports-services:
	./scripts/eureka-multi-ports-cli --action delete --count $(COUNT)

.PHONY: up-scenarios-1
up-scenarios-1:
	./scripts/scenarios.1.sh

.PHONY: down-scenarios-1
down-scenarios-1:
	export clusters="C1 C2 C3";make k3d-reset

.PHONY: up-scenarios-2
up-scenarios-2:
	./scripts/scenarios.2.sh

.PHONY: down-scenarios-2
down-scenarios-2:
	export clusters="C1 C2 C3";make k3d-reset

.PHONY: up-scenarios-3
up-scenarios-3:
	./scripts/scenarios.3.sh

.PHONY: down-scenarios-3
down-scenarios-3:
	export clusters="C1 C2 C3";make k3d-reset

.PHONY: up-scenarios-4
up-scenarios-4:
	./scripts/scenarios.4.sh

.PHONY: down-scenarios-4
down-scenarios-4:
	export clusters="C1 C2 C3";make k3d-reset

.PHONY: up-scenarios-5
up-scenarios-5:
	./scripts/scenarios.5.sh

.PHONY: down-scenarios-5
down-scenarios-5:
	export clusters="C1";make k3d-reset

.PHONY: up-scenarios-8
up-scenarios-8:
	./scripts/scenarios.8.sh

.PHONY: down-scenarios-8
down-scenarios-8:
	export clusters="C1 C2";make k3d-reset

.PHONY: up-scenarios-9
up-scenarios-9:
	./scripts/scenarios.9.sh

.PHONY: down-scenarios-9
down-scenarios-9:
	export clusters="C1";make k3d-reset

.PHONY: up-scenarios-9-1
up-scenarios-9-1:
	./scripts/scenarios.9.1.sh

.PHONY: down-scenarios-9-1
down-scenarios-9-1:
	export clusters="C1";make k3d-reset

.PHONY: up-scenarios-a
up-scenarios-a:
	./scripts/scenarios.a.sh

.PHONY: down-scenarios-a
down-scenarios-a:
	export clusters="C1 C2 C3";make k3d-reset

.PHONY: up-scenarios-b
up-scenarios-b:
	./scripts/scenarios.b.sh

.PHONY: down-scenarios-b
down-scenarios-b:
	export clusters="C1 C2 C3";make k3d-reset

.PHONY: up-scenarios-c
up-scenarios-c:
	./scripts/scenarios.c.sh

.PHONY: down-scenarios-c
down-scenarios-c:
	export clusters="C1 C2 C3";make k3d-reset

.PHONY: up-scenarios-d
up-scenarios-d:
	./scripts/scenarios.d.sh

.PHONY: down-scenarios-d
down-scenarios-d:
	export clusters="C1 C2 C3";make k3d-reset

.PHONY: up-scenarios-e
up-scenarios-e:
	./scripts/scenarios.e.sh

.PHONY: down-scenarios-e
down-scenarios-e:
	export clusters="C1 C2 C3";make k3d-reset

.PHONY: up-scenarios-f
up-scenarios-f:
	./scripts/scenarios.f.sh

.PHONY: down-scenarios-f
down-scenarios-f:
	export clusters="C1 C2 C3";make k3d-reset