{
  platform: 'kops',
  certname: 'ops.acmecorp',
  connect_obmondo: true,
  'blackbox-exporter': false,
  kube_prometheus_version: 'v0.16.0',
  grafana_keycloak_enable: true,
  grafana_root_url: 'https://grafana.ops.example.com',
  grafana_keycloak_url: 'https://keycloak.ops.example.com',
  grafana_keycloak_realm: 'MyRealm',
  grafana_ingress_host: 'grafana.ops.example.com',
  addMixins: {
    ceph: false,
    velero: true,
    opensearch: true,
  },
  prometheus+: {
    storage: {
      size: '30Gi',
      classname: 'gp2',
    },
  },
  prometheus_scrape_namespaces: ['velero', 'monitoring', 'opencost'],
}
