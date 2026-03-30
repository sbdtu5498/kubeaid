// Validates that lib/validate.libsonnet catches missing / invalid params
// and passes valid configs without errors.
//
// Run with:
//   jsonnet -J libraries/<version>/vendor tests/validate_vars_test.jsonnet
local validate = import '../lib/validate.libsonnet';

local test = import 'github.com/yugui/jsonnetunit/jsonnetunit/test.libsonnet';

// ── real-world config fixtures (imported from e2e vars) ────────────────────

local cfgKubeadmFull = import '../e2e/vars/v0.17.0/kubeadm-with-keycloak.jsonnet';
local cfgKopsVelero  = import '../e2e/vars/v0.17.0/kops-minimal.jsonnet';
local cfgKopsOps     = import '../e2e/vars/v0.17.0/kops-with-opensearch.jsonnet';
local cfgAksMinimal  = import '../e2e/vars/v0.17.0/aks-minimal.jsonnet';

// ── helpers ────────────────────────────────────────────────────────────────

local hasError(vars, substr) =
  std.length(std.filter(function(e) std.startsWith(e, substr), validate(vars))) > 0;

local noErrors(vars) = std.length(validate(vars)) == 0;

// ── tests ──────────────────────────────────────────────────────────────────

test.suite({

  // ── valid configs produce no errors ─────────────────────────────────────

  testValid_kubeadmFull: {
    actual: noErrors(cfgKubeadmFull),
    expect: true,
  },

  testValid_kopsVelero: {
    actual: noErrors(cfgKopsVelero),
    expect: true,
  },

  testValid_kopsOps: {
    actual: noErrors(cfgKopsOps),
    expect: true,
  },

  // ── platform ─────────────────────────────────────────────────────────────

  testPlatform_missing: {
    actual: hasError(cfgKubeadmFull { platform:: null } + {}, 'platform is required'),
    expect: true,
  },

  testPlatform_invalidValue: {
    actual: hasError(cfgKubeadmFull { platform: 'k3s' }, 'platform must be one of'),
    expect: true,
  },

  testPlatform_validKops: {
    actual: noErrors(cfgKopsVelero { platform: 'kops' }),
    expect: true,
  },

  testPlatform_validGke: {
    actual: noErrors(cfgKopsVelero { platform: 'gke' }),
    expect: true,
  },

  testPlatform_validEks: {
    actual: noErrors(cfgKopsVelero { platform: 'eks' }),
    expect: true,
  },

  testPlatform_validAks: {
    actual: noErrors(cfgAksMinimal),
    expect: true,
  },

  // certname validation lives in the template's assert (common-template.jsonnet)
  // not in validate.libsonnet, so there are no validator tests for it here.

  // ── grafana keycloak ─────────────────────────────────────────────────────

  testKeycloak_missingUrl: {
    local vars = cfgKubeadmFull { grafana_keycloak_url: '' },
    actual: hasError(vars, 'grafana_keycloak_url is required'),
    expect: true,
  },

  testKeycloak_missingRealm: {
    local vars = cfgKubeadmFull { grafana_keycloak_realm: '' },
    actual: hasError(vars, 'grafana_keycloak_realm is required'),
    expect: true,
  },

  testKeycloak_missingRootUrl: {
    local vars = cfgKubeadmFull { grafana_root_url: '' },
    actual: hasError(vars, 'grafana_root_url is required'),
    expect: true,
  },

  // keycloak fields not required when grafana_keycloak_enable: false
  testKeycloak_notRequiredWhenDisabled: {
    local vars = cfgKubeadmFull {
      grafana_keycloak_enable: false,
      grafana_keycloak_url: '',
      grafana_keycloak_realm: '',
      grafana_root_url: '',
    },
    actual: noErrors(vars),
    expect: true,
  },

  // ── addMixins type check ─────────────────────────────────────────────────

  testAddMixins_mustBeObject: {
    local vars = cfgKubeadmFull { addMixins: ['velero'] },
    actual: hasError(vars, 'addMixins must be an object'),
    expect: true,
  },

  // ── prometheus_scrape_namespaces type check ──────────────────────────────

  testScrapeNamespaces_mustBeArray: {
    local vars = cfgKubeadmFull { prometheus_scrape_namespaces: 'monitoring' },
    actual: hasError(vars, 'prometheus_scrape_namespaces must be an array'),
    expect: true,
  },

  // ── multiple errors returned at once ────────────────────────────────────

  testMultipleErrors_countedCorrectly: {
    local vars = {
      platform: 'kubeadm',
      connect_obmondo: false,
      grafana_keycloak_enable: true,
      grafana_keycloak_url: '',
      grafana_keycloak_realm: '',
      grafana_root_url: '',
    },
    // expects 3 errors: url, realm, root_url all missing
    actual: std.length(validate(vars)),
    expect: 3,
  },

}).verify
