// Drop specified metric endpoint paths from the kubelet ServiceMonitor
// and specific metrics from the node-exporter ServiceMonitor.
// To add more drop rules, extend the arrays below.
local epUtils = import 'endpoint-utils.libsonnet';

local dropPaths = [
  '/metrics/probes',
];

{
  kubernetesControlPlane+: {
    serviceMonitorKubelet+: {
      spec+: {
        endpoints: epUtils.dropEndpointsByPath(super.endpoints, dropPaths),
      },
    },
  },
}
