# Facilitator Solution Guide

## Grading contract

Grade immediate configuration and learner-produced evidence only. Do not require simulation results, Content Explorer counts, label propagation, Activity explorer arrival, policy-tip timing, or Insider Risk alerts. Nothing is pre-seeded: the learner creates the documents, labels, policies, simulations, and Challenge 4 evidence tags.

Microsoft 365 E5, Purview roles, Defender for Endpoint provisioning, and Purview device onboarding are operator prerequisites. The Windows VM may exist for 24 hours while deallocated outside onboarding, synchronization, telemetry, and release windows. It must report healthy onboarding, recent connectivity, and readiness for Endpoint DLP updates before delivery. The learner must not onboard or remediate it. A Temporary Access Pass is interactive handoff material, never a password or noninteractive credential. Microsoft 365 authority is separate from Azure RBAC.

Use Microsoft Edge for endpoint tests. The exact validation steps are `Validate-Zava-Discovery-Baseline`, `Validate-Zava-Information-Protection`, `Validate-Zava-Endpoint-DLP`, and `Validate-Zava-Departing-Employee-Policy-Evidence`.

## Common verification

```powershell
az account show --query '{subscription:id,tenantId:tenantId,user:user.name}' -o json
$subscriptionId = (Get-AzContext).Subscription.Id
az vm list --subscription $subscriptionId --query "[].{name:name,resourceGroup:resourceGroup,location:location,provisioning:provisioningState}" -o table
Get-AzVM -Status | Select-Object Name,ResourceGroupName,Location,ProvisioningState,PowerState
```

Expected Azure output is the approved region, `Succeeded` provisioning, and `VM running` while in use. These commands do not validate Purview. For Challenge 4, do not substitute a hard-coded resource group: resolve the VM by its exact `DeploymentID` tag as shown below. Azure Update-AzTag with `-Operation Merge` is the supported way to add or update evidence tags while preserving unrelated existing tags.

## Challenge 1 — Discover sensitive data

### Expected end state

The learner created non-live synthetic documents named exactly `Zava-Customer-Payments.docx`, `Zava-Employee-Records.docx`, and `Zava-Mixed-Sensitive-Data.docx`, and placed them across learner-created SharePoint and OneDrive locations. They reviewed and tested the built-in sensitive information types `Credit Card Number` and `U.S. Social Security Number` with synthetic values.

`Zava Discovery Baseline` exists in simulation mode. It contains advanced rule `Zava Discovery Sensitive Data Rule`, matching either named sensitive information type. Only SharePoint sites and OneDrive accounts are enabled; the other five default locations are disabled.

### Rubric

**Full credit:** exact document names and non-live content; both SIT tests; exact policy and rule; advanced rule with either-condition; simulation mode; SharePoint/OneDrive only; successful `Validate-Zava-Discovery-Baseline`.

**Partial credit:** correct policy/rule and location scope with one incomplete document placement or weak classifier evidence. A renamed document, live-looking value, enforcement mode, all-location scope, or single-SIT rule is not full credit. Do not award credit for simulation hits or Content Explorer counts.

```powershell
Connect-IPPSSession
Get-DlpCompliancePolicy -Identity 'Zava Discovery Baseline' |
  Format-List Name,Mode,SharePointLocation,OneDriveLocation,ExchangeLocation,TeamsLocation
Get-DlpComplianceRule -Identity 'Zava Discovery Sensitive Data Rule' |
  Format-List Name,Policy,ContentContainsSensitiveInformation,AdvancedRule
```

Expected output shows simulation (`TestIt` or the current portal equivalent), SharePoint and OneDrive enabled, and other locations absent or disabled. Common failures are selecting all seven defaults, creating a normal rather than advanced rule, using an AND instead of either-condition, uploading to an operator location, or using real data.

## Challenge 2 — Classify with labels and auto-labeling

### Expected end state

Unified audit logging is positively asserted with output exactly `True`. SharePoint/OneDrive Office-file labeling is enabled, and the Graph directory setting proves sensitivity labels are enabled for Microsoft 365 groups and sites.

The labels have these exact settings:

| Label | Required setting |
|---|---|
| `Zava Public` | No protection |
| `Zava Internal` | Header text `Zava Internal` |
| `Zava Confidential` | Encryption for internal users only; watermark `Confidential` |
| `Zava Highly Confidential` | Scope files, emails, groups, and sites; encryption; watermark `Highly Confidential`; external sharing limited to people in the organization |

`Zava Global Label Policy` publishes all four labels. `Zava Auto-Label Policy` is simulation-only, applies `Zava Highly Confidential`, and contains `Zava High-Risk Identity Data Rule`. That rule matches either `Credit Card Number` or `U.S. Social Security Number`, with minimum count 5 for each. Automatic activation after seven days is off.

Any DLP policy conditioned on a sensitivity label must exclude Teams and use only Exchange, SharePoint, and OneDrive.

### Rubric

**Full credit:** audit output `True`; SharePoint integration true; Graph directory-setting proof; all four labels with exact settings; exact publishing policy membership; exact simulated auto-labeling policy/rule and counts; no Teams in any sensitivity-label-conditioned DLP; successful `Validate-Zava-Information-Protection`.

**Partial credit:** correct labels and policy with one non-critical presentation setting or evidence item missing. Audit output other than `True`, missing Graph proof, Teams selected, wrong count, or seven-day activation enabled is material. Never grade propagation or simulation output.

```powershell
Connect-ExchangeOnline
$auditingEnabled = -not (Get-OrganizationConfig).AuditDisabled
$auditingEnabled
# Expected: True

Connect-SPOService -Url 'https://TENANT_DOMAIN-admin.sharepoint.com'
Set-SPOTenant -EnableAIPIntegration $true
Get-SPOTenant | Select-Object EnableAIPIntegration
# Expected: True

Connect-MgGraph -Scopes 'Directory.ReadWrite.All','Directory.AccessAsUser.All'
Get-MgDirectorySetting | Where-Object DisplayName -eq 'Group.Unified' |
  Select-Object DisplayName,Values
# Expected: EnableMIPLabels = True
```

Use the current Purview portal to inspect label details, publication, auto-labeling, and any label-conditioned DLP locations. Do not treat a missing banner as audit proof. Common failures include wrong SharePoint admin tenant, missing directory setting, protecting `Zava Internal`, omitting groups/sites from `Zava Highly Confidential`, selecting Teams, or storing a Temporary Access Pass in a script.

## Challenge 3 — Endpoint Data Loss Prevention

### Expected end state

The device list at Settings > Device onboarding > Devices is empty. That is the expected state: this lab tenant onboards no device, and Challenge 3 is graded on policy configuration only. A learner who reports an empty device list and explains the Defender for Endpoint sensor dependency has answered Task 1 correctly.

These exact Devices-only policies and rules exist, each with a content condition matching either `Credit Card Number` or `U.S. Social Security Number`:

- `Zava Block Removable Storage` / `Zava Block Sensitive Data to Removable Storage Rule`: block copy to removable media.
- `Zava Block Unsanctioned Cloud Uploads` / `Zava Block Sensitive Uploads to Unsanctioned Cloud Rule`: block `Upload to a restricted cloud service domain` for `Zava Unsanctioned Cloud Storage`.
- `Zava Block Generative AI Sharing` / `Zava Block Sensitive Data to Generative AI Rule`: block both `Upload to a restricted cloud service domain` and `Paste to supported browsers` for built-in, non-editable `Generative AI Websites`.

`Zava Unsanctioned Cloud Storage` contains exactly `dropbox.com`, `drive.google.com`, and `box.com`. The learner tests `Zava-Endpoint-Sensitive-Data.txt` in Edge and interprets the observed block/policy-tip evidence. Sync and telemetry delay are instructional caveats, not grading inputs.

### Rubric

**Full credit:** correct statement of the onboarded-device dependency and the empty device list; exact three policies/rules; Devices-only scope; either-SIT conditions; correct block actions; exact custom domain group and domains; built-in `Generative AI Websites`; both generative-AI actions; risk interpretation; successful `Validate-Zava-Endpoint-DLP`.

**Partial credit:** configuration is exact but one physical removable-media test is unavailable and the operator confirms device readiness. Missing content conditions, wrong domain/group, non-Devices scope, or one missing generative-AI action is material. Do not deduct for delayed Activity explorer events.

```powershell
Connect-IPPSSession
Get-DlpCompliancePolicy | Where-Object Name -in @(
 'Zava Block Removable Storage','Zava Block Unsanctioned Cloud Uploads',
 'Zava Block Generative AI Sharing'
) | Format-List Name,Mode,EndpointDlpLocation,ExchangeLocation,SharePointLocation,OneDriveLocation
Get-DlpComplianceRule -Policy 'Zava Block Removable Storage' |
  Format-List Name,ContentContainsSensitiveInformation,EndpointDlpRestrictions
```

Expected output is three enforcing Devices-only policies with the specified rules. Inspect action semantics and domain membership in the current Purview portal because endpoint-DLP API property names vary. Expected learner interpretation: removable-media exfiltration, unsanctioned-cloud upload, and generative-AI paste/upload are three distinct risks.

Common failures: learner attempts onboarding, testing before sync, using Chrome/Firefox without the Purview extension, creating a replacement AI group, confusing sensitive service domain groups with Restricted apps and app groups, omitting content conditions, or treating absent telemetry as failure.

## Challenge 4 — Insider risk detection for departing users

### Expected end state

The four current-portal indicators covering SharePoint sharing, SharePoint downloads, and external email with attachments are enabled. The facilitator confirms the current Microsoft Learn-aligned labels and that global indicators were not confused with policy indicators.

`Zava Departing Employee Data Theft` was created from `Data theft by departing users` using **Custom policy**, not Quick policy, with Microsoft Entra account deleted as the triggering event. Both `Content to prioritize` wizard pages were completed and the selected indicators preserved.

The single Azure VM resolved in the current subscription by an exact, case-sensitive `DeploymentID` tag match carries exactly these seven canonical evidence tags and values:

| Tag | Required value |
|---|---|
| `ZavaIRPolicy` | `Zava Departing Employee Data Theft` |
| `ZavaIRTemplate` | `Data theft by departing users` |
| `ZavaIRPolicyType` | `Custom policy` |
| `ZavaIRTrigger` | `Microsoft Entra account deleted` |
| `ZavaIRPriorityPages` | `Both confirmed` |
| `ZavaIRIndicators` | `Sharing SharePoint files with people outside the organization;Sharing SharePoint folders with people outside the organization;Downloading content from SharePoint;Sending email with attachments to recipients outside the organization` |
| `ZavaIREvidenceUtc` | A parseable UTC ISO 8601 timestamp, recorded after the guided portal cross-check |

The existing `DeploymentID`, `LabCode`, and every other deployment/platform tag remain intact. The evidence is cloud-visible on the resolved VM; no local evidence file is part of the expected state.

### Rubric

**Full credit:** exact four indicators; exact template, Custom policy, and deletion trigger; both wizard-page confirmations; exactly one VM resolved by `DeploymentID`; all seven canonical tags with exact values; the four indicators appear in the required order with semicolon delimiters and no additional separators; `ZavaIREvidenceUtc` parses as UTC; `DeploymentID`, `LabCode`, and other deployment tags are preserved; optional facilitator portal inspection confirms the same policy settings; successful `Validate-Zava-Departing-Employee-Policy-Evidence`.

**Partial credit:** portal configuration is correct but one tag value is missing or the learner has not yet demonstrated preservation of deployment tags; award no more than partial until the exact tag contract is repaired. A correct policy with a hard-coded resource group, multiple matching VMs, altered `DeploymentID`/`LabCode`, reordered indicators, extra delimiters, local-file evidence, or a non-UTC/unparseable timestamp is not full credit. Do not grade alert generation.

#### Required VM resolution and tag update

The facilitator should require a single-VM result before any write. `$DID` below represents the injected deployment ID; use the current subscription context, not a guessed resource-group name. `Update-AzTag -Operation Merge` adds or updates only the seven evidence tags and preserves the complete existing tag set, consistent with the Azure `Update-AzTag` guidance.

```powershell
$subscriptionId = (Get-AzContext).Subscription.Id
$deploymentId = $DID
$vms = @(Get-AzVM -ErrorAction Stop | Where-Object {
    $_.Tags -and $_.Tags.ContainsKey('DeploymentID') -and
    [string]$_.Tags['DeploymentID'] -ceq $deploymentId
})
if ($vms.Count -ne 1) {
    throw "Expected exactly one VM with DeploymentID=$deploymentId; found $($vms.Count)."
}
$vm = $vms[0]
$before = @{} + $vm.Tags

$indicators = 'Sharing SharePoint files with people outside the organization;Sharing SharePoint folders with people outside the organization;Downloading content from SharePoint;Sending email with attachments to recipients outside the organization'
$evidenceTags = @{
    ZavaIRPolicy       = 'Zava Departing Employee Data Theft'
    ZavaIRTemplate     = 'Data theft by departing users'
    ZavaIRPolicyType   = 'Custom policy'
    ZavaIRTrigger      = 'Microsoft Entra account deleted'
    ZavaIRPriorityPages = 'Both confirmed'
    ZavaIRIndicators   = $indicators
    ZavaIREvidenceUtc  = [DateTime]::UtcNow.ToString('o')
}
Update-AzTag -ResourceId $vm.Id -Tag $evidenceTags -Operation Merge -ErrorAction Stop | Out-Null

$after = (Get-AzResource -ResourceId $vm.Id -ExpandProperties -ErrorAction Stop).Tags
$evidenceTags.GetEnumerator() | ForEach-Object {
    if ([string]$after[$_.Key] -cne [string]$_.Value) { throw "Tag $($_.Key) failed exact verification." }
}
if ([string]$after['DeploymentID'] -cne [string]$before['DeploymentID'] -or
    [string]$after['LabCode'] -cne [string]$before['LabCode']) {
    throw 'DeploymentID or LabCode was changed.'
}
$after.GetEnumerator() | Sort-Object Key | Format-Table Key,Value -AutoSize
```

The equivalent CLI read is useful for a facilitator, but the write must preserve tags rather than replace them:

```powershell
az resource show --ids $vm.Id --query tags -o json
az vm show -g $vm.ResourceGroupName -n $vm.Name --query tags -o json
```

Do not use `New-AzTag` or a replace operation for this task. Do not put passwords, access tokens, Temporary Access Pass values, tenant identifiers, personal data, user content, or alert details in Azure tags.

#### Optional manual facilitator portal inspection

This is an optional manual cross-check, separate from automated validation and not a substitute for the VM-tag contract. In Microsoft Edge, inspect `Zava Departing Employee Data Theft` in Purview and confirm the template, Custom policy workflow, Microsoft Entra account-deleted trigger, both content-priority pages, and the four selected indicators. An empty alerts queue is expected: an alert requires a triggering event, matching activity, and a risk score above threshold. Do not direct the learner to a Cases tab or claim that alert state proves success.

### Common failures

- Resolving by a guessed resource group or VM name instead of finding exactly one VM by `DeploymentID`.
- Writing tags before checking the match count, matching `DeploymentID` case-insensitively, or accepting zero/multiple matches.
- Using `Replace` or otherwise removing `DeploymentID`, `LabCode`, or platform deployment tags instead of `Update-AzTag -Operation Merge`.
- Using aliases, dots, underscores, reordered indicators, commas, spaces around semicolons, or additional evidence tags; the seven names and values are exact.
- Recording a local evidence file instead of writing the seven tags to the resolved VM, or writing a non-UTC/unparseable timestamp.
- Quick policy, HR connector/termination event, enabled global indicator not preserved in content priority, or stale portal terminology accepted without current-label review.
- Treating evidence validation as a tenant-state query or treating an empty queue as failure.

## Operator troubleshooting

- **E5 or role access missing:** stop; assign Microsoft 365 E5 and all five named role groups, then allow propagation.
- **Wrong tenant:** compare `TenantId`, learner UPN, and SharePoint admin URL; reconnect to the intended tenant.
- **Automated validator authentication failure:** authentication is noninteractive certificate app-only only. Repair the operator-managed app registration, certificate installation in the validation account's `CurrentUser\\My` store, certificate thumbprint/application/organization variables, or required API and Exchange/Security & Compliance role assignments. Install a current `ExchangeOnlineManagement` version where required. There is no interactive, device-code, Temporary Access Pass, username/password, or constructed-credential fallback. This validator's Challenge 4 check is Azure-only and does not initiate a Microsoft 365 connection.
- **VM image or SKU unavailable:** verify the approved Windows publisher/offer/SKU in the target region. Pilot `Standard_B2s`; use `Standard_B2ms` only as the documented capacity fallback, preserving the package image contract and tags.
- **CSE extension failure:** inspect the VM extension provisioning status and bootstrap logs; repair the common-assets download, PowerShell prerequisites, or browser tooling before release. Do not put tenant secrets in bootstrap files or logs.
- **Device unhealthy/not ready:** verify Defender provisioning, Purview onboarding package, current connectivity, and readiness for Endpoint DLP policy updates; repair and recheck before delivery.
- **VM tag update denied or incomplete:** verify the learner/operator has the package-scoped VM tag-write permission and that Azure RBAC has propagated. Do not grant Owner or tenant-wide authority. Re-read tags after `Update-AzTag -Operation Merge`.
- **VM deallocated:** resources may intentionally remain deployed for 24 hours while the VM is deallocated outside onboarding, synchronization, telemetry, and release windows. Start it only for the required operational window; deallocation alone is not a deployment failure.
- **Label-conditioned DLP error:** remove Teams; retain Exchange, SharePoint, and OneDrive. `SensitivityLabelsNotSupportedForNonSupportedWorkloadsException` indicates invalid scope.
- **No endpoint tip/event:** allow sync and telemetry delay; grade configuration and health, not delayed output.

## Final decision

Pass when all four exact validations succeed and qualitative evidence confirms the four challenge end states. Delayed simulation results, Content Explorer counts, label propagation, Activity explorer events, and Insider Risk alerts are never required for passing.

Consult current Microsoft Learn guidance for Microsoft Purview DLP, endpoint DLP, sensitivity labels, SharePoint/OneDrive labeling integration, Graph directory settings, unified audit logging, Insider Risk Management, [certificate-based app-only Exchange Online PowerShell](https://learn.microsoft.com/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps), and [Update-AzTag](https://learn.microsoft.com/powershell/module/az.resources/update-aztag). Preserve the canonical names and invariants above when portal wording changes.