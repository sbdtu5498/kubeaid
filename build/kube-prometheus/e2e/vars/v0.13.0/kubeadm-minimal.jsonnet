{
  platform: 'kubeadm',
  certname: 'prod.acmecorp',
  connect_obmondo: true,
  'blackbox-exporter': false,
  kube_prometheus_version: 'v0.13.0',
  addMixins: {
    velero: true,
    mdraid: true,
  },
  prometheus+: {
    storage: {
      size: '10Gi',
      classname: 'standard',
    },
  },
}
