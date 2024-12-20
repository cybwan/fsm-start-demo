#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

CTR_REGISTRY="${CTR_REGISTRY:-cybwan}"
CTR_TAG="${CTR_TAG:-1.5.0-alpha.4}"
CTR_XNET_TAG="${CTR_XNET_TAG:-latest}"
IMAGE_PULL_POLICY="${IMAGE_PULL_POLICY:-Always}"

fsm_namespace="${fsm_namespace:-fsm-system}"
fsm_mesh_name="${fsm_mesh_name:-fsm}"

fsm_cluster_name="${fsm_cluster_name:-fsm}"

sidecar="${sidecar:-NodeLevel}"

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
    --timeout=900s