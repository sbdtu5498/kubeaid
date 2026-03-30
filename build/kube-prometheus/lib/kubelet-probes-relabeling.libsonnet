// Drops process_start_time_seconds from the /metrics/probes kubelet endpoint
// to prevent PrometheusDuplicateTimestamps — this metric is also exposed by
// /metrics with an identical timestamp, causing Prometheus to discard samples.
{
  kubernetesControlPlane+: {
    serviceMonitorKubelet+: {
      spec+: {
        endpoints: std.map(
          function(ep)
            if std.get(ep, 'path', '/metrics') == '/metrics/probes'
            then ep {
              metricRelabelings+: [{
                sourceLabels: ['__name__'],
                regex: 'process_start_time_seconds',
                action: 'drop',
              }],
            }
            else ep,
          super.endpoints
        ),
      },
    },
  },
}
