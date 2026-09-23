# Know Your Data - Discover, Classify and Protect Sensitive Information with Microsoft Purview

This CloudLabs package delivers a six-hour, intermediate Azure challenge lab in which a learner helps Zava discover regulated data, classify it with sensitivity labels, prevent endpoint exfiltration, and configure insider-risk detection for departing users. The environment combines a dedicated Azure Windows 11 VM with a preassigned Microsoft 365 E5 tenant and Microsoft Purview services.

## Package contents

- `README.md`
- `Spec.md`
- `DeploymentPackage/deploy-01.json`
- `DeploymentPackage/deploy-01.parameters.json`
- `DeploymentPackage/psscript-01.ps1`
- `LabGuidePackage/Lab Guide/Lab Guide/GettingStarted-V2.md`
- `LabGuidePackage/Lab Guide/Lab Guide/Challenge-01-Discover-Sensitive-Data.md`
- `LabGuidePackage/Lab Guide/Lab Guide/Challenge-02-Classify-With-Labels-And-Auto-Labeling.md`
- `LabGuidePackage/Lab Guide/Lab Guide/Challenge-03-Endpoint-Data-Loss-Prevention.md`
- `LabGuidePackage/Lab Guide/Lab Guide/Challenge-04-Insider-Risk-For-Departing-Users.md`
- `LabGuidePackage/Lab Guide/Lab Guide/media/zava-purview-architecture.svg`
- `Validations/Validate-Zava-Discovery-Baseline.ps1`
- `Validations/Validate-Zava-Information-Protection.ps1`
- `Validations/Validate-Zava-Endpoint-DLP.ps1`
- `Validations/Validate-Zava-Departing-Employee-Policy-Evidence.ps1`
- `solution-guide/solution.md`
- `permissions/CustomRBAC/custom-rbac-role.json`
- `permissions/CustomARMPolicy/azure-policy.json`

All learner-facing guide filenames, headings, and prose use **Challenge** terminology.

## Challenge outline

1. **Discover sensitive data (55 minutes):** Create synthetic documents and configure `Zava Discovery Baseline` with `Zava Discovery Sensitive Data Rule` in simulation mode for SharePoint and OneDrive only.
2. **Classify with labels and auto-labeling (75 minutes):** Verify tenant prerequisites, create and publish `Zava Public`, `Zava Internal`, `Zava Confidential`, and `Zava Highly Confidential`, and simulate `Zava Auto-Label Policy` with `Zava High-Risk Identity Data Rule`.
3. **Endpoint Data Loss Prevention (60 minutes):** Verify the healthy pre-onboarded endpoint and create Devices-only controls for removable storage, unsanctioned cloud storage, and the built-in `Generative AI Websites` domain group.
4. **Insider risk detection for departing users (45 minutes):** Enable the four required indicators, configure `Zava Departing Employee Data Theft` from `Data theft by departing users` as a `Custom policy` with the `Microsoft Entra account deleted` trigger, confirm both content-priority pages, perform the guided portal cross-check, and record the seven exact evidence tags on the Azure VM resolved by `DeploymentID`.

The remaining scheduled time covers environment orientation, prerequisite verification, policy propagation allowances, evidence review, and validation.

## Azure deployment boundary

A single ARM stage deploys the Windows 11 lab endpoint and its Azure boundary: virtual machine, network interface, virtual network, network security group, public IP, `StandardSSD_LRS` managed OS disk, boot diagnostics, Custom Script Extension, and the existing enabled `Microsoft.DevTestLab/schedules` VM shutdown schedule. Preserve that schedule and its target, time, time zone, and notification settings; do not create a second schedule. The Custom Script Extension downloads common bootstrap assets from `experienceazure.blob.core.windows.net/templates/cloudlabs-common/`, installs current PowerShell prerequisites and browser tooling, and prepares synthetic-data helper files without writing tenant secrets to files or logs.

Use separate Azure role assignments. Assign the deployment identity the packaged deployment-capable custom role at the deployment scope required to create and manage the ARM resources. Assign the learner the tag-capable role at the scope of the single lab VM only; that VM-scoped assignment supports the seven Challenge 4 evidence tags without granting deployment-wide resource management. Neither assignment grants tenant-wide Microsoft 365 authority, and neither permits Azure role-assignment write or delete operations.

Azure Policy is limited to the Azure resource boundary. It enforces the approved Windows 11 image/SKU contract, managed disks, and required deployment tags `LabCode` and `DeploymentID`; it does not govern Microsoft 365 or Microsoft Purview configuration. `Standard_B2ms` with `StandardSSD_LRS` is the deployed size. `Standard_B2s` was the original baseline but is subject to capacity restrictions in East US — a deployment on 2026-09-23 failed preflight with `SkuNotAvailable ... Capacity Restrictions: Standard_B2s`. Both sizes remain permitted by the Azure Policy, so reverting is a one-value change if capacity returns.

ARM, CSE, Azure RBAC, and Azure Policy do not assign Microsoft 365 licenses or Purview roles, provision the Defender for Endpoint tenant, or onboard the device to Microsoft Purview. Those operations are operator-managed hot-instance prerequisites.

## Operator hot-instance prerequisites

The Azure resources can remain provisioned for at least 24 hours while the VM is deallocated outside explicit onboarding, synchronization, telemetry, and release-verification windows. Complete and verify all items before releasing the lab:

1. Keep the hot-instance resources provisioned for at least 24 hours before learner access. Do not interpret this as a requirement to keep the VM running continuously.
2. Confirm the guest operating system is Windows 11 and preserve the existing enabled VM shutdown schedule without changing its established settings.
3. Assign Microsoft 365 E5 to the learner identity.
4. Assign Global Administrator and the following Microsoft Purview role groups, allowing time for propagation:
   - `Information Protection`
   - `Content Explorer List Viewer`
   - `Content Explorer Content Viewer`
   - `Insider Risk Management`
   - `Compliance Administrator`
5. Complete Microsoft Defender for Endpoint tenant provisioning.
6. Obtain the current onboarding package through an operator-secured process, onboard the Windows VM to Microsoft Purview, and confirm successful onboarding, current connectivity, healthy status, and readiness to receive Endpoint DLP policy updates.
7. Confirm Microsoft Edge is installed. If Chrome or Firefox is made available, install the Microsoft Purview extension before using either browser for endpoint controls.
8. Attach a removable-storage test device or configure operator-approved removable-media emulation.
9. Provide a Temporary Access Pass through the designated handoff field only. It is not the learner's password and must never be placed in a script, file, log, environment variable, certificate secret, or noninteractive credential object.
10. Apply the two separate Azure role assignments described above and ensure the validation identity can read the single VM and its tags.
11. Install the validation certificate in the Windows validation account's `CurrentUser\My` certificate store and inject the three-variable app-only validation contract described below.

Use this start/deallocate checklist for every explicit onboarding, synchronization, telemetry, or release-verification window:

1. Start the deallocated VM and wait until Azure reports it running and the guest is reachable.
2. Perform only the scheduled onboarding, policy-sync, connectivity, telemetry, or release checks.
3. Before release, confirm Microsoft Purview reports successful onboarding, current connectivity, healthy status, and readiness for Endpoint DLP policy updates.
4. When the window is complete and no learner session or required operation is active, deallocate the VM and verify Azure reports `PowerState/deallocated`.
5. Repeat the start checks before the learner window. The auto-shutdown schedule is deployed **disabled**. This lab is pre-deployed as a hot instance at least 24 hours before delivery so Defender for Endpoint tenant provisioning and device onboarding can complete; a daily shutdown during that window stops the VM while nobody is connected and silently breaks the warm-up. Deallocate deliberately after each operator window instead, and re-enable the schedule only if this lab is ever delivered without a pre-deployment window.

The learner verifies health but does not onboard or remediate the device. If licensing, role propagation, onboarding, connectivity, or health checks fail, the learner stops and contacts the lab operator.

## Challenge 4 Azure VM-tag evidence contract

Challenge 4 uses seven Azure VM tags and never mutates `LabCode` or writes local JSON evidence. Resolve the resource by finding exactly one `Microsoft.Compute/virtualMachines` resource in the current subscription whose existing `DeploymentID` tag equals the injected deployment ID. Do not hard-code or derive a resource-group name.

After the guided portal cross-check, merge these seven exact tags into that VM:

- `ZavaIRPolicy` = `Zava Departing Employee Data Theft`
- `ZavaIRTemplate` = `Data theft by departing users`
- `ZavaIRPolicyType` = `Custom policy`
- `ZavaIRTrigger` = `Microsoft Entra account deleted`
- `ZavaIRPriorityPages` = `Both confirmed`
- `ZavaIRIndicators` = `Sharing SharePoint files with people outside the organization;Sharing SharePoint folders with people outside the organization;Downloading content from SharePoint;Sending email with attachments to recipients outside the organization`
- `ZavaIREvidenceUtc` = a parseable UTC ISO 8601 timestamp recorded after the portal cross-check

Use Azure tag merge semantics, such as `Update-AzTag -Operation Merge`, so all existing deployment tags, including `LabCode` and `DeploymentID`, remain unchanged. Do not replace the VM tag set, mutate `LabCode`, create a local JSON evidence file or template, or place secrets or tenant identifiers in tags.

The learner's VM-scoped role assignment must permit tag updates only at the single VM boundary. Do not prepopulate any of the seven evidence tags. The Challenge 4 validator resolves the VM by `DeploymentID`, validates all seven values, and does not depend on guest filesystem access. Because Microsoft Learn does not document a supported Insider Risk Management PowerShell cmdlet for this policy-state query, the tags record the required guided portal cross-check and do not claim to prove tenant policy state or alert generation.

## Learner starting state

The learner begins by positively checking for Microsoft 365 E5 at `https://portal.office.com/account/#subscriptions`. If the license is absent, the learner stops because downstream symptoms can be misleading.

Nothing is pre-seeded. There are no sample documents, sensitivity labels, completed simulation results, HR connector data, existing insider-risk alerts, local evidence JSON files, or Challenge 4 evidence tags. The VM already has the platform deployment tags `LabCode` and `DeploymentID`; both remain unchanged. Security Copilot is not provisioned and is not required.

## Configuration invariants

- Unified audit logging must be positively queried and the verification output must equal `True`; the absence of a portal warning or banner is not evidence.
- SharePoint and OneDrive Office-file labeling is enabled with `Set-SPOTenant -EnableAIPIntegration $true` and then verified from the tenant property.
- Sensitivity labels for Microsoft 365 groups and sites are enabled and verified through Microsoft Graph PowerShell; there is no portal substitute for this directory setting.
- Any DLP policy conditioned on a sensitivity label is scoped only to Exchange, SharePoint, and OneDrive. Teams must not be selected, preventing `SensitivityLabelsNotSupportedForNonSupportedWorkloadsException`.
- `Zava Auto-Label Policy` remains in simulation mode and automatic activation after seven days is not enabled.
- Each endpoint DLP rule includes a sensitive-content condition and is scoped only to Devices.
- The unsanctioned storage group is exactly `Zava Unsanctioned Cloud Storage` with `dropbox.com`, `drive.google.com`, and `box.com`.
- The generative-AI control references the built-in, non-editable `Generative AI Websites` group; no replacement group is created.
- Microsoft Edge is the required validation browser. Chrome and Firefox require the Microsoft Purview extension.
- Delayed simulation results, Content Explorer counts, label application, endpoint policy sync, policy tips, Activity explorer events, and insider-risk alert generation are instructional evidence and are not passing criteria.

## Validation contract

The four shipped validation paths and visible validation names are retained exactly:

1. `Validate-Zava-Discovery-Baseline` → `Validations/Validate-Zava-Discovery-Baseline.ps1`
2. `Validate-Zava-Information-Protection` → `Validations/Validate-Zava-Information-Protection.ps1`
3. `Validate-Zava-Endpoint-DLP` → `Validations/Validate-Zava-Endpoint-DLP.ps1`
4. `Validate-Zava-Departing-Employee-Policy-Evidence` → `Validations/Validate-Zava-Departing-Employee-Policy-Evidence.ps1`

Every Microsoft 365 validator connection uses exactly this operator-injected app-only certificate contract:

- `M365_VALIDATOR_APP_ID`: Microsoft Entra application ID.
- `M365_VALIDATOR_ORGANIZATION`: tenant primary `.onmicrosoft.com` organization.
- `M365_VALIDATOR_CERT_THUMBPRINT`: thumbprint of the certificate installed in the Windows validation account's `CurrentUser\My` certificate store.

Security & Compliance PowerShell connects noninteractively with `Connect-IPPSSession -AppId $env:M365_VALIDATOR_APP_ID -Organization $env:M365_VALIDATOR_ORGANIZATION -CertificateThumbprint $env:M365_VALIDATOR_CERT_THUMBPRINT`; Exchange Online connections, where required, use the same three values with `Connect-ExchangeOnline`. Validators fail clearly if a variable is absent, the certificate cannot be resolved, or app-only connection fails. There is no interactive, device-code, username/password, Temporary Access Pass, or other fallback. Tenant ID, base64 PFX, PFX password, and SharePoint Online URL are not required contract variables. The certificate private key and values remain operator-managed and never appear in learner files, ARM outputs, inject keys, or logs.

Grant the validation service principal only the Microsoft 365 application permissions and Exchange/Security & Compliance role assignments required by the checks, plus Azure read access at the single VM scope for the Challenge 4 evidence validator. Separately, grant the deployment identity its required deployment-scope Azure role assignment and the learner its tag-capable assignment at the single VM scope. None uses a learner password or Temporary Access Pass.

Validators inspect immediate configuration state only and follow the CloudLabs Azure PowerShell response contract. The first three validators inspect supported tenant configuration surfaces but do not grade delayed telemetry or simulation outcomes. If the information-protection validator examines a sensitivity-label-conditioned DLP object, it requires Teams to be absent and permits only Exchange, SharePoint, and OneDrive.

`Validate-Zava-Departing-Employee-Policy-Evidence.ps1` is deliberately evidence-based. It resolves exactly one VM by the `DeploymentID` tag, validates the seven exact merged evidence tags and UTC timestamp, and confirms that existing deployment tags including `LabCode` are not the evidence carrier. It does not access local JSON, claim to query the tenant policy, or use an empty alerts queue as proof. Alerts require a triggering event, matching activity, and a risk score above threshold.

## Microsoft product references

Implementation guidance was aligned with current Microsoft Learn documentation for certificate-based app-only Exchange Online and Security & Compliance PowerShell, Azure tag merge behavior, DevTestLab schedules, and the built-in managed-disk policy. Portal labels and workflows can change, so operators must recheck the current pages at release time:

- App-only authentication for unattended Exchange Online PowerShell and Security & Compliance PowerShell: https://learn.microsoft.com/powershell/exchange/app-only-auth-powershell-v2
- `Update-AzTag` and `Merge` operation semantics: https://learn.microsoft.com/powershell/module/az.resources/update-aztag
- `Microsoft.DevTestLab/schedules` ARM resource reference: https://learn.microsoft.com/azure/templates/microsoft.devtestlab/schedules
- Azure Policy built-in definitions for Virtual Machines, including managed-disk auditing: https://learn.microsoft.com/azure/virtual-machines/policy-reference
- Microsoft Graph permissions reference: https://learn.microsoft.com/graph/permissions-reference
- Temporary Access Pass: https://learn.microsoft.com/entra/identity/authentication/howto-authentication-temporary-access-pass
- Tag resources, resource groups, and subscriptions: https://learn.microsoft.com/azure/azure-resource-manager/management/tag-resources
- Azure VM auto-shutdown: https://learn.microsoft.com/azure/devtest-labs/devtest-lab-auto-shutdown
- Microsoft Purview licensing: https://learn.microsoft.com/purview/purview
- Learn about data loss prevention: https://learn.microsoft.com/purview/dlp-learn-about-dlp
- Endpoint data loss prevention: https://learn.microsoft.com/purview/endpoint-dlp-learn-about
- Get started with sensitivity labels: https://learn.microsoft.com/purview/get-started-with-sensitivity-labels
- Enable sensitivity labels for files in SharePoint and OneDrive: https://learn.microsoft.com/purview/sensitivity-labels-sharepoint-onedrive-files
- Enable sensitivity label support for groups and sites: https://learn.microsoft.com/purview/sensitivity-labels-teams-groups-sites
- Learn about auto-labeling policies: https://learn.microsoft.com/purview/apply-sensitivity-label-automatically
- Learn about Insider Risk Management: https://learn.microsoft.com/purview/insider-risk-management
- Create an Insider Risk Management policy: https://learn.microsoft.com/purview/insider-risk-management-policies
- Onboard Windows devices into Microsoft Purview: https://learn.microsoft.com/purview/device-onboarding-overview

## Security and support

Do not embed tenant secrets, onboarding packages, access tokens, certificate material, certificate passwords, or Temporary Access Pass values in package artifacts or logs. Operator-only onboarding and validation material must be retrieved securely and kept outside learner-facing content.

Lab support:

- Email: `cloudlabs-support@spektrasystems.com`
- Portal: https://cloudlabs.ai/labs-support
