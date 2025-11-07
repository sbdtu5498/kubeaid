// based on Prometheus alert by GitHub user raqqun:
// https://github.com/vmware-tanzu/velero/issues/2725#issuecomment-661577500
{
  _config+:: {
    selector: '',
  },

  prometheusAlerts+:: {
    groups+: [
      {
        name: 'velero',
        rules: [
          {
            alert: 'VeleroUnsuccessfulBackup',
            expr: |||
              (
                ((time() - velero_backup_last_successful_timestamp{schedule=~".*6hrly.*"}) + on(schedule) group_left velero_backup_attempt_total > (60 * 60 * 6) and ON() hour() >= 6.30 <= 18.30)
                or
                ((time() - velero_backup_last_successful_timestamp{schedule=~".*daily.*"}) + on(schedule) group_left velero_backup_attempt_total > (60 * 60 * 24) and ON() day_of_week() != 0)
                or
                ((time() - velero_backup_last_successful_timestamp{schedule=~".*weekly.*"}) + on(schedule) group_left velero_backup_attempt_total > (60 * 60 * 24 * 7))
              )
            ||| % $._config,
            'for': '15m',
            labels: {
              severity: 'warning',
              schedule: '{{ $labels.schedule }}'
            },
            annotations: {
              description: 'Velero backup was not successful for {{ $labels.schedule }}.',
              summary: 'Velero backup for schedule was unsuccessful.',
            },
          },
          {
            alert: 'VeleroNoFirstSuccessfulBackup',
            expr: |||
              (
                (absent(velero_backup_success_total{schedule=~".*(daily|6hrly|weekly).*"} ) or (velero_backup_success_total{schedule=~".*(daily|6hrly|weekly).*", schedule!=""} == 0)) and on() (up{pod=~".*velero.*"} == 1)
              )
            ||| % $._config,
            'for': '15m',
            labels: {
              severity: 'critical',
              schedule: '{{ $labels.schedule }}'
            },
            annotations: {
              summary: "Velero backup has not completed once successfully for any schedule.",
              description:
                "{{- with $labels.schedule -}} No successful Velero backups have been detected for schedule: {{ . }} while the Velero pod is running.This likely indicates a configuration or permission issue preventing backups from completing. {{- else -}} Velero backup metrics are missing while the Velero pod is running. This may indicate that the backup metric is not being emitted or there is a configuration/permission issue. {{- end }}"
            },
          },
        ],
      },
    ],
  },
}
