// Reusable functions for modifying ServiceMonitor endpoints.
//
// Usage examples:
//
//   local epUtils = import 'lib/endpoint-utils.libsonnet';
//
//   // Drop an entire endpoint path from a ServiceMonitor:
//   {
//     someComponent+: {
//       serviceMonitor+: {
//         spec+: {
//           endpoints: epUtils.dropEndpointsByPath(super.endpoints, ['/metrics/probes']),
//         },
//       },
//     },
//   }
//
//   // Drop specific metrics by name from all endpoints in a ServiceMonitor
//   // (e.g. drop node_cpu_seconds_total from node-exporter):
//   {
//     nodeExporter+: {
//       serviceMonitor+: {
//         spec+: {
//           endpoints: epUtils.dropMetricsByName(
//             super.endpoints, ['node_cpu_seconds_total', 'node_cpu_guest_seconds_total']
//           ),
//         },
//       },
//     },
//   }
{
  // Drop entire endpoints by path via relabeling.
  dropEndpointsByPath(endpoints, dropPaths)::
    std.map(
      function(ep)
        if std.member(dropPaths, std.get(ep, 'path', ''))
        then ep {
          relabelings: [{
            action: 'drop',
            sourceLabels: ['__metrics_path__'],
            regex: std.get(ep, 'path', ''),
          }],
        }
        else ep,
      endpoints,
    ),

  // Drop specific metrics by name via metricRelabelings.
  dropMetricsByName(endpoints, metricNames)::
    std.map(
      function(ep)
        ep {
          metricRelabelings+: [{
            sourceLabels: ['__name__'],
            regex: std.join('|', metricNames),
            action: 'drop',
          }],
        },
      endpoints,
    ),
}
