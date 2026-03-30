{
  platform: 'aks',
  certname: 'dev.acmecorp',
  connect_obmondo: true,
  'blackbox-exporter': false,
  kube_prometheus_version: 'v0.16.0',
  addMixins: {
    ceph: false,
    velero: true,
  },
  prometheus+: {
    storage: {
      size: '10Gi',
      classname: 'managed-premium',
    },
  },
  prometheus_scrape_namespaces: ['velero'],
}
