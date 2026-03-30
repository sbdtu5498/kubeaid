{
  platform: 'kops',
  certname: 'dev.acmecorp',
  connect_obmondo: true,
  'blackbox-exporter': false,
  kube_prometheus_version: 'v0.14.0',
  addMixins: {
    ceph: false,
    velero: true,
  },
  prometheus+: {
    storage: {
      size: '10Gi',
      classname: 'gp2',
    },
  },
  prometheus_scrape_namespaces: ['velero'],
}
