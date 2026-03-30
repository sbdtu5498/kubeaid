// Validates a vars object before the template is compiled.
// Returns an array of error strings. Empty array means valid.
//
// Usage in common-template.jsonnet:
//   local validate = import 'lib/validate.libsonnet';
//   local errors = validate(vars);
//   assert std.length(errors) == 0 :
//     '\n\nVars validation failed:\n' + std.join('\n', ['  - ' + e for e in errors]);

function(vars)
  local check(condition, msg) = if !condition then msg else null;

  local errors = std.filter(
    function(e) e != null,
    [
      // ── always required ────────────────────────────────────────────────

      check(
        std.objectHas(vars, 'platform'),
        'platform is required (one of: kops, kubeadm, gke, eks)',
      ),

      if std.objectHas(vars, 'platform') then
        check(
          std.member(['kops', 'kubeadm', 'gke', 'eks'], vars.platform),
          'platform must be one of: kops, kubeadm, gke, eks (got: "%s")' % vars.platform,
        ),

      // ── grafana_keycloak_enable: true requires related fields ─────────

      if std.get(vars, 'grafana_keycloak_enable', false) then
        check(
          std.objectHas(vars, 'grafana_keycloak_url') && vars.grafana_keycloak_url != '',
          'grafana_keycloak_url is required when grafana_keycloak_enable is true',
        ),

      if std.get(vars, 'grafana_keycloak_enable', false) then
        check(
          std.objectHas(vars, 'grafana_keycloak_realm') && vars.grafana_keycloak_realm != '',
          'grafana_keycloak_realm is required when grafana_keycloak_enable is true',
        ),

      if std.get(vars, 'grafana_keycloak_enable', false) then
        check(
          std.objectHas(vars, 'grafana_root_url') && vars.grafana_root_url != '',
          'grafana_root_url is required when grafana_keycloak_enable is true',
        ),

      // ── type checks ───────────────────────────────────────────────────

      if std.objectHas(vars, 'addMixins') then
        check(
          std.type(vars.addMixins) == 'object',
          'addMixins must be an object (got: %s)' % std.type(vars.addMixins),
        ),

      if std.objectHas(vars, 'prometheus_scrape_namespaces') then
        check(
          std.type(vars.prometheus_scrape_namespaces) == 'array',
          'prometheus_scrape_namespaces must be an array',
        ),

      if std.objectHas(vars, 'prometheus_scrape_default_namespaces') then
        check(
          std.type(vars.prometheus_scrape_default_namespaces) == 'array',
          'prometheus_scrape_default_namespaces must be an array',
        ),
    ]
  );

  errors
