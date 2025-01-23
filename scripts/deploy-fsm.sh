#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

CTR_REGISTRY="${CTR_REGISTRY:-flomesh}"
CTR_TAG="${CTR_TAG:-1.5.0-alpha.3}"
CTR_XNET_TAG="${CTR_XNET_TAG:-latest}"
IMAGE_PULL_POLICY="${IMAGE_PULL_POLICY:-Always}"

fsm_namespace="${fsm_namespace:-fsm-system}"
fsm_mesh_name="${fsm_mesh_name:-fsm}"

fsm_cluster_name="${fsm_cluster_name:-fsm}"

sidecar="${sidecar:-NodeLevel}"
k8s="${k8s:-false}"
mesh="${mesh:-true}"
e4lb="${e4lb:-false}"

dns_svc_ip="$(kubectl get svc -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].spec.clusterIP}')"
clusters="${clusters:-c0}"

fsm install \
    --mesh-name "$fsm_mesh_name" \
    --fsm-namespace "$fsm_namespace" \
    --set=fsm.image.registry="$CTR_REGISTRY" \
    --set=fsm.image.tag="$CTR_TAG" \
    --set=fsm.image.pullPolicy="$IMAGE_PULL_POLICY" \
    --set=fsm.trafficInterceptionMode="$sidecar" \
    --set=fsm.fsmXnetwork.xnet.image.registry="$CTR_REGISTRY" \
    --set=fsm.fsmXnetwork.xnet.image.tag="$CTR_XNET_TAG" \
    --set=fsm.fsmXnetwork.xnet.nodePaths.k8s.enable="${k8s}" \
    --set=fsm.fsmXnetwork.xnet.features.mesh="${mesh}" \
    --set=fsm.fsmXnetwork.xnet.features.e4lb="${e4lb}" \
    --set=fsm.sidecar.sidecarLogLevel=debug \
    --set=fsm.sidecar.compressConfig=false \
    --set=fsm.sidecar.image.registry="$CTR_REGISTRY" \
    --set=fsm.repoServer.image.registry="$CTR_REGISTRY" \
    --set=fsm.controllerLogLevel=warn \
    --set=clusterSet.region=LN \
    --set=clusterSet.zone=DL \
    --set=clusterSet.group=FLOMESH \
    --set=clusterSet.name="$fsm_cluster_name" \
    --set=fsm.localDNSProxy.enable=true \
    --set=fsm.localDNSProxy.wildcard.enable=true \
    --set=fsm.localDNSProxy.wildcard.ips[0].ipv4="1.1.1.1" \
    --set=fsm.localDNSProxy.wildcard.los[0].ipv4="127.0.0.1" \
    --set=fsm.localDNSProxy.primaryUpstreamDNSServerIPAddr=$dns_svc_ip \
    --set fsm.fsmIngress.enabled=false \
    --set fsm.fsmGateway.enabled=true \
    --set fsm.fsmGateway.logLevel=debug \
    --set fsm.featureFlags.enableValidateHTTPRouteHostnames=false \
    --set fsm.featureFlags.enableValidateGRPCRouteHostnames=false \
    --set fsm.featureFlags.enableValidateTLSRouteHostnames=false \
    --set fsm.featureFlags.enableValidateGatewayListenerHostname=false \
    --set=fsm.featureFlags.enableSidecarPrettyConfig=true \
    --set=fsm.fsmBootstrap.resource.requests.cpu=0.1 \
    --set=fsm.fsmBootstrap.resource.requests.memory=128M \
    --set=fsm.injector.resource.requests.cpu=0.1 \
    --set=fsm.injector.resource.requests.memory=128M \
    --set=fsm.fsmController.resource.requests.cpu=0.1 \
    --set=fsm.fsmController.resource.requests.memory=256M \
    --set=fsm.fsmXnetwork.xmgt.resource.requests.cpu=0.1 \
    --set=fsm.fsmXnetwork.xmgt.resource.requests.memory=256M \
    --set=fsm.fsmXnetwork.xnet.resource.requests.cpu=0.1 \
    --set=fsm.fsmXnetwork.xnet.resource.requests.memory=256M \
    --timeout=900s