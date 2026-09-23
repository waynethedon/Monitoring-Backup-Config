# Monitoring-Backup-Config

This project demonstrates hands-on Azure Monitor and Backup configuration for the VM/RBAC environment: a Log Analytics workspace connected via the Azure Monitor Agent and a Data Collection Rule, a host-level CPU alert rule, a KQL query for operational analysis, and a full Azure Backup setup (Recovery Services Vault, backup policy, and a verified restore point). The environment is defined as reusable Infrastructure-as-Code using Bicep where the resource type supports it.

## Architecture

- **Log Analytics Workspace**: `law-vmrbac-project` (North Central US) — central destination for VM telemetry
- **Azure Monitor Agent (AMA)**: installed on `vm1` as a VM extension, deployed via Bicep
- **Data Collection Rule (DCR)**: `dcr-vm1-metrics`, collecting the `Percentage CPU` performance counter and routing it to the Log Analytics workspace via a `Microsoft-Perf` data flow
- **Data Collection Rule Association**: links the DCR directly to `vm1`
- **CPU Alert Rule**: `alert-vm1-high-cpu`, a host-level metric alert (`Percentage CPU` > 80%, 5-minute window) that doesn't depend on the Azure Monitor Agent, notifying via an existing action group by email
- **KQL Query**: a gap-detection query against the `Heartbeat` table, surfacing periods where the monitoring agent stopped reporting
- **Recovery Services Vault**: `rsv-vmrbac-project` (North Central US), configured with an Enhanced backup policy (required for Trusted Launch VMs) — daily backup, 7-day retention
- **Backup verification**: an on-demand backup completed successfully, producing a confirmed restore point
- **Infrastructure as Code**: the Azure Monitor Agent extension, DCR, DCR association, and CPU alert rule are defined in `monitoring.bicep`; the Recovery Services Vault and backup policy were configured manually and are not yet codified

**Note**: monitoring and backup are two entirely separate, unrelated pipelines protecting the same VM — the Log Analytics workspace stores telemetry/observability data, while the Recovery Services Vault stores backup/recovery data. Neither feeds into the other.

*(Architecture diagram included below/attached)*

## Key decisions

**Host-level metric alert instead of guest-level.** The CPU alert rule uses the platform's `Percentage CPU` metric, collected directly by the Azure hypervisor, rather than the Azure Monitor Agent's guest-level performance counter. This was a deliberate choice after the guest-level counter pipeline (see Challenges) proved unreliable despite exhaustive troubleshooting — the host-level metric is simpler, has no agent dependency, and is the more common real-world approach for basic CPU alerting anyway.

**Enhanced backup policy, not Standard.** `vm1` uses Trusted Launch (Secure Boot + vTPM), which Azure's Standard backup policy tier doesn't support — Enhanced is required. This wasn't a preference; the Portal rejected Standard outright with a clear validation error tied to the VM's own security configuration from Project 1.

**File-level restore instead of full VM restore.** Given this is a cost-conscious lab environment, I chose file-level restore over a full VM restore to verify recoverability — it avoids the cost and time of spinning up a second temporary VM while still exercising a genuine, complete restore operation.

**Monitoring is only partially in Bicep.** The Azure Monitor Agent extension, DCR, DCR association, and alert rule are all defined in `monitoring.bicep`. The Recovery Services Vault and backup policy are not — they were configured manually via the Portal. This is a deliberate scope decision for this pass, not an oversight: backup infrastructure is often managed separately from application/workload infrastructure in real organizations (frequently owned by a different team), so treating it as a distinct manual configuration is a reasonably realistic reflection of how backup policy ownership is often split from day-to-day IaC.

## Challenges & troubleshooting

**Auto-generated resources kept getting blocked by the tag-enforcement Policy — a recurring pattern.** The Portal's VM Insights wizard tried to create a Data Collection Rule without a tag, and the CLI's `az vm extension set` command has no `--tags` flag at all — both got denied by the same Policy that's blocked auto-generated resources in earlier projects. Confirmed this is Azure Policy's "Indexed" mode working exactly as designed (it only skips resource types that structurally cannot support tags at all, not ones a particular tool simply failed to tag). Fixed both by writing standalone Bicep resources with explicit tags instead of relying on Portal wizards or CLI shortcuts.

**The monitoring agent couldn't reach Azure at all.** After deploying the full monitoring pipeline, zero data appeared in Log Analytics — not even a basic heartbeat. The root cause was Project 2's own `Deny-Outbound-Internet` NSG rule, built for a different, earlier security goal, silently blocking the Azure Monitor Agent. Diagnosed methodically, layer by layer: confirmed via `curl` that the agent's control-plane and authentication endpoints were unreachable, then found that three separate NSG allow rules were required for three separate Azure service tags (`AzureMonitor`, `AzureResourceManager`, and `AzureActiveDirectory`, the last needed for the agent's authentication step specifically). Heartbeat data began flowing once all three were opened.

**The same outbound block resurfaced during the backup restore.** Performing a file-level restore required installing a system package (`acl`) and a Python compatibility shim (`pyasyncore`) directly on the VM — both blocked by the same `Deny-Outbound-Internet` rule that caused the earlier monitoring outage. Resolved by temporarily disabling the rule for the duration of the installs, then re-enabling it immediately afterward — a legitimate, time-boxed "maintenance window" pattern rather than a permanent loosening of the security posture.

## Verification

- **Monitoring pipeline alive**: `Heartbeat | take 10` in Log Analytics returns consistent rows from `vm1`, roughly one per minute, confirming the Azure Monitor Agent is reporting correctly
- **Outbound restriction working**: `curl` from inside the VM to an arbitrary internet host times out, confirming the NSG's deny-outbound-internet rule is active outside of temporary maintenance windows
- **CPU alert rule deployed**: confirmed via the Bicep deployment's `provisioningState: Succeeded`
- **Backup completed and restore point confirmed**:

- az backup recoverypoint list --resource-group rg-vmrbac-project --vault-name rsv-vmrbac-project --container-name vm1 --item-name vm1 --backup-management-type AzureIaasVM returned a real recovery point, timestamped from a completed on-demand backup job — this is the actual proof Azure Backup requires: a real, restorable snapshot exists
- **File-level restore attempted, not completed**: Azure's file-recovery script satisfied every documented prerequisite (correct package dependencies, network access to the recovery endpoint, correct connection password) and successfully authenticated the iSCSI connection to the recovery point, but the disk-attach step stalled indefinitely and never produced a mounted volume. After a patient, extended wait with no further progress, the process was stopped and the connection cleanly closed via the Portal's "Unmount Disks" option rather than left running

## How to deploy

```bash
git clone https://github.com/waynethedon/Monitoring-Backup-Config.git
cd Monitoring-Backup-Config
az login
az deployment group create \
  --resource-group <your-resource-group> \
  --template-file monitoring.bicep
```

This deploys the Azure Monitor Agent extension, the Data Collection Rule, the DCR-to-VM association, and the CPU alert rule. It assumes an existing VM and Log Analytics workspace are already present (see [VM-RBAC-Config](https://github.com/waynethedon/VM-RBAC-Config) for the VM).

The Recovery Services Vault and backup policy are not included in this template and must be configured separately via the Portal or CLI — see Key Decisions for why.

**Important**: if the target VM has an outbound-restrictive NSG (as this project's VM does), ensure outbound HTTPS (443) is allowed to the `AzureMonitor`, `AzureResourceManager`, and `AzureActiveDirectory` service tags before deploying, or the monitoring agent will silently fail to report any data.

## Next steps

- Investigate the unresolved file-level restore stall further, or attempt a full VM restore instead as an alternate verification path
- Codify the Recovery Services Vault and backup policy in Bicep
- Revisit the guest-level `Perf` performance counter pipeline if time allows — the host-level metric alert works well as a substitute, but the original goal of guest-level telemetry remains unmet
- Project 6 will build on this vault directly, with a goal of performing and fully verifying a real restore
