
# Opendesk Setup
🚨 WARNING: The secrets used in opendesk.
- are stored in plain text across all projects in this repository.
- DO NOT make the config repository public.
- DO NOT share access with non-admin users. it is a limitation on the upstream repo.

## Index

1. [Installation](#installation)
2. [Running the Build Script](#running-the-build-script)
3. [Upgrade Procedure](#upgrade-procedure)
4. [Adding New Release to Build Versions](#adding-new-release-to-build-versions)
5. [Overriding Jitsi Values (JVB_STUN_SERVERS and Jibri)](#example-overriding-jvb_stun_servers-and-jibri-in-opendesk-jitsi)
6. [Adding Missing Configuration Using Custom Go Template Values Files](#adding-missing-configuration-using-custom-go-template-values-files)
7. [Application Testing Procedure (Before and After Upgrade)](#application-testing-procedure-before-and-after-upgrade)

   * [Pre-Upgrade Checklist](#pre-upgrade-checklist)
   * [Functional Testing (Baseline)](#functional-testing-baseline)
   * [Post-Upgrade Testing](#post-upgrade-testing)


## Installation

**Note:** Self-registration is not supported in Opendesk. 
1. **Basic Requirements**
   Ensure all prerequisites are met as described here:
   [https://gitlab.opencode.de/bmi/opendesk/deployment/opendesk/-/blob/develop/docs/requirements.md#tldr](https://gitlab.opencode.de/bmi/opendesk/deployment/opendesk/-/blob/develop/docs/requirements.md#tldr)

2. **Helm Version**
   The Helm version must be lower than `3.18.0`. 
   Our testing was performed using Helm version `3.17.4`.
   [source](https://gitlab.opencode.de/bmi/opendesk/deployment/opendesk/-/blob/develop/docs/requirements.md?plain=1#L33)

3. **Storage Class Requirement**
   The StorageClass used in your cluster **must have the sticky bit enabled**.
   This is a limitation of `openproject`.
   Reference: [https://github.com/opf/helm-charts/blob/main/charts/openproject/templates/_helpers.tpl#L90](https://github.com/opf/helm-charts/blob/main/charts/openproject/templates/_helpers.tpl#L90)

   **Note:** Currently, it is not possible to specify the StorageClass name via the Opendesk values file. The default StorageClass will always be used.

4. **DKIM Configuration**
   Use [https://easydmarc.com/tools/dkim-record-generator](https://easydmarc.com/tools/dkim-record-generator) to generate a DKIM key pair for the domain that will be used to send emails.

   * Selector: `default`
   * Key length: `4096`

   The tool will provide a DNS TXT record similar to:

   ```
   Publish the following DNS TXT record on default._domainkey.$domain subdomain
   ```

   Add this TXT record to your DNS configuration.

   Copy the generated private key and create a Kubernetes secret named:

   ```
   opendesk-dkimpy-milter
   ```
5. Additionally, Coturn is deployed separately using https://github.com/Obmondo/KubeAid/tree/master/argocd-helm-charts/opendesk-coturn , as Opendesk supports only an external TURN server.
---

## Running the Build Script

The build script requires the ABSOLUTE path to the `kubeaid-config` repository directory that contains the values file.

A sample values file is available here:
`./examples/values.yaml`

**Important:**

* The path provided must be an absolute path.
* The values file must be named `values-opendesk.yaml`.

Run the script as follows:

```bash
./build.sh $kubeaid-config-values-file-directory-absolute-path
```

Example path:

```
/home/testuser/kubeaid-config/k8s/$clustername/argocd-apps
```

After execution, the script will generate:

* Core Opendesk applications in:

  ```
  kubeaid-config/k8s/$clustername/opendesk-essentials/opendesk-essentials.yaml
  ```

  These **MUST** be synced first.

* Other applications (e.g., mail, chat) in:

  ```
  kubeaid-config/k8s/$clustername/opendesk/mail/mail.yaml
  kubeaid-config/k8s/$clustername/opendesk/chat/chat.yaml
  ```

**Note:**
Applications such as Chat and Webmail require users of type `opendesk-user` to be created.

Additional information about Opendesk services is available here:
`./docs/opendesk-services-description.md`


### Upgrade Procedure

- To perform an upgrade, update the version in the `build.sh` script and execute the script as above.
- The process typically takes around **15–20 minutes** to complete.

- Ensure that any manual changes are committed separately.

- Follow the below tests before and after the upgrade [Link](./README.md#1-pre-upgrade-checklist)

- The script supports generating manifests for individual applications using flags, allowing specific components to be regenerated without affecting others (to save time).

However, we **do not recommend upgrading individual applications independently to higher versions**, as compatibility is tested at the Opendesk release level.

These flags are mainly intended for configuration-related updates. For example, you can regenerate only the Jitsi manifests after disabling the Jibri plugin via values:

```bash
./build.sh <target-directory> --only-jitsi
```

Use individual component flags carefully and ensure version compatibility with the current Opendesk release.


---

## Adding Missing Configuration Using Custom Go Template Values Files

In some cases, certain Helm chart values may not be available in the default helmfile application values.

For example, in the `openproject` chart, the `tmpVolumesStorageClassName` option was not present in:

```
./versions/v1.6.0/helmfile/apps/openproject/
```

To add such missing configurations:

1. Create a custom Go template values file named:

   ```
   values-<app>.yaml.gotmpl
   ```

   inside the `value-files` directory
   (Example: `./value-files/values-openproject.yaml.gotmpl`)

2. Add default values for the new configuration in:

   ```
   ./default-values/values.yaml
   ```

3. Reference the custom values file in the Helmfile release section within:

   ```
   ./default-values/values.yaml
   ```

   Example:

   ```yaml
   customization:
     release:
       <app>:
         - "../../../../../value-files/values-<app>.yaml.gotmpl"
   ```

Follow this process to introduce any missing configurations for Opendesk Helmfile applications.

## Example: Overriding `JVB_STUN_SERVERS` and Jibri `enable` in Opendesk (Jitsi)

In this example, we will override:

* `JVB_STUN_SERVERS`
* Jibri configuration

This section explains how to trace where values are defined and at which level they can be overridden.

---

### 1.Understanding the Override Hierarchy

Opendesk uses Helmfile to deploy Jitsi. The value resolution order is:

```
Upstream jitsi-helm (dependency)
        ↓
opendesk-jitsi chart
        ↓
values-jitsi.yaml.gotmpl (helmfile layer)
        ↓
your values-opendesk.yaml (highest priority)
```

Your `values-opendesk.yaml` always has the highest precedence.

---

### 2.Start With Opendesk Helmfile Values

Opendesk defines Jitsi values here:

```
build/opendesk/versions/v1.11.4/helmfile/apps/jitsi/values-jitsi.yaml.gotmpl
```

These values can be overridden via your custom `values-opendesk.yaml`.
IF you didn't find the value here proceed to next step

---

### 3.Check Which Chart Is Used

To identify the upstream chart:

```
build/opendesk/versions/v1.11.4/helmfile/apps/jitsi/helmfile-child.yaml.gotmpl
```

This file references the chart:

[https://gitlab.opencode.de/bmi/opendesk/components/platform-development/charts/opendesk-jitsi](https://gitlab.opencode.de/bmi/opendesk/components/platform-development/charts/opendesk-jitsi)

---

### 4.Check Default Chart Values

Open:

[https://gitlab.opencode.de/bmi/opendesk/components/platform-development/charts/opendesk-jitsi/-/blob/main/charts/opendesk-jitsi/values.yaml](https://gitlab.opencode.de/bmi/opendesk/components/platform-development/charts/opendesk-jitsi/-/blob/main/charts/opendesk-jitsi/values.yaml)

If the value exists here, it can be overridden directly.if it is not present here proceed to next step

---

### 5.Check Chart Dependencies

Some values are not defined in `opendesk-jitsi` because they come from dependencies.

Check dependencies in:

[https://gitlab.opencode.de/bmi/opendesk/components/platform-development/charts/opendesk-jitsi/-/blob/main/charts/opendesk-jitsi/Chart.yaml](https://gitlab.opencode.de/bmi/opendesk/components/platform-development/charts/opendesk-jitsi/-/blob/main/charts/opendesk-jitsi/Chart.yaml)

Example: `JVB_STUN_SERVERS`

This value comes from the upstream dependency:

[https://github.com/jitsi-contrib/jitsi-helm/blob/main/values.yaml](https://github.com/jitsi-contrib/jitsi-helm/blob/main/values.yaml)

If it is not defined in the Opendesk values file, you must override it at the correct nested level.

---

### 6.Example Override commit
[commit](https://gitea.obmondo.com/EnableIT/KubeAid/pulls/1249/commits/22d440a872bc6e0ca1a0da9d25276ed48e607d6c)



---

### 7.Regenerate Only Jitsi

```bash
./build.sh <target-directory> --only-jitsi
```

---

## How to Debug Value Overrides

If a value is not taking effect:

1. Check `values-jitsi.yaml.gotmpl`
2. Check `helmfile-child.yaml.gotmpl`
3. Check `opendesk-jitsi` chart `values.yaml`
4. Check `Chart.yaml` for dependencies
5. Check dependency chart `values.yaml`
6. Override in `values-opendesk.yaml`



## Application Testing Procedure (Before and After Upgrade)

To ensure a safe upgrade, testing **must be performed both before and after the upgrade**. The goal is to validate functionality, confirm no data loss, and ensure backups are available for rollback if required.

### 1. Pre-Upgrade Checklist

Before starting the upgrade:

1. **Verify Backups**

   * Confirm that database backups are successfully completed.
   * Verify file storage backups (documents, attachments, uploads).
   * Ensure backup restoration has been tested previously.
   * Record backup timestamps.

2. **Record Current State**

   * Note current application version.
   * Take screenshots of key application dashboards.
   * Record number of:

     * Users
     * Projects
     * Tasks
     * Calendar events
     * Files
     * Emails (mailbox counts)


### Functional Testing (Baseline)

Perform and document the following tests in detail:

**Jitsi Meet:**
Host meetings with up to 6 participants simultaneously. Verify that audio and video quality are clear and stable. Test screen sharing functionality and confirm that chat messages are delivered correctly during the session. Ensure participants can join and leave without issues.

**Mail:**
Send and receive emails internally and externally. Verify that attachments can be uploaded and downloaded without corruption. Confirm proper email threading and delivery to intended recipients.

**Calendar:**
Create appointments and view them across different user profiles. Send invitations to other users and confirm they can accept or decline without issues. Ensure calendar events are properly integrated with email and that acceptance notifications are received.

**File Store:**
Upload new files, download existing files, and share files between users. Confirm access permissions work correctly and that previously stored files remain accessible.

**Chat Application:**
Send direct messages and create group conversations. Verify real-time message delivery and confirm that users can access previous chat history without issues.

**Wiki Application:**
Create a new wiki page or blog post. Edit existing content and confirm that changes are saved correctly. Verify that the content is visible and accessible to other users based on permissions.

**Task Application:**
Create new tasks, assign them to other users, and update task statuses. Confirm that email notifications for task assignments and updates are received successfully.

**Contacts Application:**
Add new contacts and create distribution lists. Share distribution lists with other users. Send bulk emails using mailing lists and schedule appointments using distribution lists, ensuring email invitations are delivered successfully.

All results must be documented. This documentation serves as the baseline comparison for post-upgrade validation.


### 2. Post-Upgrade Testing

After the upgrade:

* Confirm the new version is deployed.
* Verify **no data loss** (users, projects, tasks, events, files, emails).
* Compare data counts with the pre-upgrade baseline.
* Repeat key functional tests (mail, meeting, calendar, files, chat, tasks).
* Confirm backups are running successfully after the upgrade.

## New release
To add a new Opendesk release to the build system to Kubeaid:

1. Go to the official Opendesk repository:
   [https://gitlab.opencode.de/bmi/opendesk/deployment/opendesk/](https://gitlab.opencode.de/bmi/opendesk/deployment/opendesk/)

2. Switch to the required release version (for example: `v1.11.4`).

3. Download the release files for that version.

4. Add the downloaded version directory to the following path in KubeAid:
   [https://github.com/Obmondo/KubeAid/tree/master/build/opendesk/versions](https://github.com/Obmondo/KubeAid/tree/master/build/opendesk/versions)

5. Ensure the directory name matches the release version exactly (e.g., `v1.11.4`).

After adding the new version, update `build.sh` to reference the new version directory before generating manifests.

## Backup and restore using Velero

Ensure all the [required volumes](https://docs.opendesk.eu/operations/data-storage) are backed up by adding the below annotations in your kubeaid-config values file.

```yaml
annotations:
  servicesExternalMinio:
    pod:
      backup.velero.io/backup-volumes: "data"
  servicesExternalPostgresql:
    pod:
      backup.velero.io/backup-volumes: "data"
  servicesExternalMariadb:
    pod:
      backup.velero.io/backup-volumes: "data"
  openxchangeDovecot:
    pod:
      backup.velero.io/backup-volumes: "srv-mail,var-lib-dovecot"
  xwiki:
    common:
      backup.velero.io/backup-volumes: "xwiki-data"
  elementSynapse:
    pod:
      backup.velero.io/backup-volumes: "media"
  nubusLdapNotifier:
    pod:
      backup.velero.io/backup-volumes: "shared-data,shared-run"
  nubusLdapServer:
    pod:
      backup.velero.io/backup-volumes: "shared-data,shared-run"
  nubusUdmListener:
    pod:
      backup.velero.io/backup-volumes: "data"
  nubusProvisioning:
    pod:
      backup.velero.io/backup-volumes: "nats-data"
  servicesExternalPostfix:
    pod:
      backup.velero.io/backup-volumes: "spool-postfix"
  openxchangePostfix:
    pod:
      backup.velero.io/backup-volumes: "spool-postfix"
  elementMatrixNeodatefixBot:
    pod:
      backup.velero.io/backup-volumes: "data"
  nubusOxConnector:
    pod:
      backup.velero.io/backup-volumes: "ox-connector-appcenter,ox-connector-ox-contexts"
```

*Note*: Adding `backup.velero.io/backup-volumes` annotation is currently not supported by opendesk for the below volumes:
- nats-data volume(v1.6.0, v1.11.4):
   - In the generated `opendesk-essentials.yaml`, add the below annotation in `ums-provisioning-nats` statefulSet under `.spec.template.metadata.annotations`

   ```yaml
      backup.velero.io/backup-volumes: "nats-data"
   ```
- xwiki-data volume(v1.6.0, v1.11.4):
   - In the generated `xwiki.yaml`, add the below annotation in `xwiki` statefulSet under `.spec.template.metadata.annotations`

   ```yaml
      backup.velero.io/backup-volumes: "xwiki-data"
   ```

- spool-postfix volume(v1.6.0):
   - In the generated `mail.yaml`, add the below annotation in `postfix` statefulSet under `.spec.template.metadata.annotations`

   ```yaml
      backup.velero.io/backup-volumes: "spool-postfix"
   ```

Velero backup and restore commands can be found [here](../../argocd-helm-charts/velero/README.md)