# Challenge 02: Classify with labels and auto-labeling

### Estimated Duration: 75 minutes

## Scenario

Zava needs a consistent classification scheme that distinguishes public, internal, confidential, and highly confidential information. You will establish the tenant prerequisites, create and publish four sensitivity labels, and configure a service-side auto-labeling policy that identifies high-risk identity data without changing production content.

## Overview

In this challenge, you will positively verify unified auditing, enable sensitivity-label processing for SharePoint and OneDrive, enable labels for Microsoft 365 groups and sites, create the exact Zava label taxonomy, publish it globally, and run an auto-labeling policy in simulation mode.

## Objectives

- Task 1: Positively verify unified auditing
- Task 2: Enable labeling for SharePoint and OneDrive
- Task 3: Enable labeling for Microsoft 365 groups and sites
- Task 4: Create the four Zava sensitivity labels
- Task 5: Publish the Zava labels
- Task 6: Configure service-side auto-labeling simulation
- Task 7: Verify the immediate configuration

## Task 1: Positively verify unified auditing

In this task, you will use Exchange Online PowerShell to prove that unified audit ingestion is enabled. A missing portal banner is not proof that auditing is enabled.

1. On the lab VM, open **Windows PowerShell** as administrator and connect interactively to Exchange Online. Complete any browser sign-in prompt with the learner administrator account.

   ```powershell
   Import-Module ExchangeOnlineManagement
   Connect-ExchangeOnline -ShowBanner:$false
   ```

2. Read the current setting. If it is false, enable it, wait for the service to accept the change, and then read it again.

   ```powershell
   $auditEnabled = [bool](Get-AdminAuditLogConfig).UnifiedAuditLogIngestionEnabled
   if (-not $auditEnabled) {
       Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true
       Start-Sleep -Seconds 60
       $auditEnabled = [bool](Get-AdminAuditLogConfig).UnifiedAuditLogIngestionEnabled
   }
   $auditEnabled
   if (-not $auditEnabled) {
       throw "UnifiedAuditLogIngestionEnabled must return True before you continue."
   }
   ```

3. Confirm that the final assertion output is exactly:

   ```text
   True
   ```

> [!Important] Run `Get-AdminAuditLogConfig` in the Exchange Online session, not the Security & Compliance session. Microsoft documents that the same property can incorrectly appear as `False` in Security & Compliance PowerShell.

> [!Important] Do not continue unless the positive assertion prints `True`. If the setting remains false after 60 minutes, contact the lab operator.

## Task 2: Enable labeling for SharePoint and OneDrive

In this task, you will enable Office-file sensitivity-label processing in SharePoint and OneDrive and positively verify the tenant property.

1. Copy the SharePoint admin URL supplied with the lab. In the same elevated PowerShell window, connect interactively when prompted.

   ```powershell
   Import-Module Microsoft.Online.SharePoint.PowerShell
   $spoAdminUrl = Read-Host "Paste the SharePoint admin URL"
   Connect-SPOService -Url $spoAdminUrl
   ```

2. Enable the integration and confirm the prompt if one appears.

   ```powershell
   Set-SPOTenant -EnableAIPIntegration $true
   ```

3. Verify the tenant property with this exact assertion.

   ```powershell
   $aipIntegrationEnabled = [bool](Get-SPOTenant).EnableAIPIntegration
   $aipIntegrationEnabled
   if (-not $aipIntegrationEnabled) {
       throw "EnableAIPIntegration must return True before you continue."
   }
   ```

4. Confirm that the assertion output is `True`.

> [!Note] This tenant-level change can take approximately 15 minutes to take effect. The immediate property assertion must still return `True` before you continue.

## Task 3: Enable labeling for Microsoft 365 groups and sites

In this task, you will use Microsoft Graph PowerShell to set `EnableMIPLabels` on the tenant-wide `Group.Unified` directory setting. There is no portal substitute for this setting.

1. Install or update the required Microsoft Graph modules, then connect with delegated directory-setting permission.

   ```powershell
   Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber
   Install-Module Microsoft.Graph.Beta.Identity.DirectoryManagement -Scope CurrentUser -Force -AllowClobber
   Import-Module Microsoft.Graph.Authentication
   Import-Module Microsoft.Graph.Beta.Identity.DirectoryManagement
   Connect-MgGraph -Scopes "Directory.ReadWrite.All"
   ```

2. Retrieve the tenant-wide `Group.Unified` setting. If it does not exist, create it from the official `Group.Unified` template with `EnableMIPLabels` set to `True`. If it exists, update that value.

   ```powershell
   $grpUnifiedSetting = Get-MgBetaDirectorySetting | Where-Object DisplayName -eq "Group.Unified"

   if (-not $grpUnifiedSetting) {
       $templateId = (Get-MgBetaDirectorySettingTemplate | Where-Object DisplayName -eq "Group.Unified").Id
       $params = @{
           templateId = $templateId
           values = @(
               @{
                   name  = "EnableMIPLabels"
                   value = "True"
               }
           )
       }
       $grpUnifiedSetting = New-MgBetaDirectorySetting -BodyParameter $params
   }
   else {
       $params = @{
           values = @(
               @{
                   name  = "EnableMIPLabels"
                   value = "True"
               }
           )
       }
       Update-MgBetaDirectorySetting -DirectorySettingId $grpUnifiedSetting.Id -BodyParameter $params
   }
   ```

3. Run the exact verification commands. They retrieve the setting again, display the name and value, and require a positive Boolean assertion.

   ```powershell
   $grpUnifiedSetting = Get-MgBetaDirectorySetting | Where-Object DisplayName -eq "Group.Unified"
   $mipLabelSetting = $grpUnifiedSetting.Values | Where-Object Name -eq "EnableMIPLabels"
   $mipLabelSetting | Format-Table Name, Value -AutoSize
   $mipLabelsEnabled = [bool]::Parse($mipLabelSetting.Value)
   $mipLabelsEnabled
   if (-not $mipLabelsEnabled) {
       throw "EnableMIPLabels must return True before you continue."
   }
   ```

4. Confirm that the table shows `EnableMIPLabels` with value `True` and that the final assertion prints `True`.

> [!Important] This setting enables sensitivity-label support for Microsoft 365 groups and their connected sites. It does not create a group, a team, or a SharePoint site.

## Task 4: Create the four Zava sensitivity labels

In this task, you will create the four labels in increasing sensitivity order with the exact scopes and protection settings below.

1. In Microsoft Edge, open <https://purview.microsoft.com>, then go to **Solutions** > **Information Protection** > **Sensitivity labels**.

2. Create `Zava Public` with these exact settings:

   - **Scope**: **Files & other data assets** and **Emails**
   - **Protection settings for files and emails**: none selected
   - **Auto-labeling for files and emails**: off
   - **Protection**: no encryption and no content markings

3. Create `Zava Internal` with these exact settings:

   - **Scope**: **Files & other data assets** and **Emails**
   - **Content marking**: on
   - **Header**: on
   - **Header text**: `Zava Internal`
   - **Footer**: off
   - **Watermark**: off
   - **Encryption**: off
   - **Auto-labeling for files and emails**: off

4. Create `Zava Confidential` with these exact settings:

   - **Scope**: **Files & other data assets** and **Emails**
   - **Content marking**: on
   - **Watermark**: on
   - **Watermark text**: `Confidential`
   - **Header** and **Footer**: off
   - **Encryption**: on
   - **Assign permissions now**: selected
   - **Users and groups**: all users and groups in the organization
   - **Permissions**: **Co-Author**
   - **User access to content expires**: **Never**
   - **Offline access**: **Never expires**
   - **Auto-labeling for files and emails**: off

5. Create `Zava Highly Confidential` with these exact settings:

   - **Scope**: **Files & other data assets**, **Emails**, and **Groups & sites**
   - **Content marking**: on
   - **Watermark**: on
   - **Watermark text**: `Highly Confidential`
   - **Header** and **Footer**: off
   - **Encryption**: on
   - **Assign permissions now**: selected
   - **Users and groups**: all users and groups in the organization
   - **Permissions**: **Co-Author**
   - **User access to content expires**: **Never**
   - **Offline access**: **Never expires**
   - **Privacy and external user access settings**: on
   - **External user access**: off
   - **External sharing and Conditional Access settings**: on
   - **Control external sharing from labeled SharePoint sites**: **Only people in your organization**
   - **Conditional Access**: not configured
   - **Auto-labeling for files and emails**: off

6. Review the label list and confirm the order from lowest to highest sensitivity is `Zava Public`, `Zava Internal`, `Zava Confidential`, and `Zava Highly Confidential`. Use the move controls if the order differs.

> [!Note] The visual watermark configured on a label is not stamped onto SharePoint or OneDrive documents by a service-side auto-labeling policy. The label and its encryption settings are still the required policy target.

## Task 5: Publish the Zava labels

In this task, you will publish all four labels to all users and synchronize container-capable labels to Microsoft Entra ID.

1. In the Microsoft Purview portal, go to **Solutions** > **Information Protection** > **Publishing policies**, then select **Publish label**.

2. Configure the publishing policy with these exact values:

   - **Labels to publish**: `Zava Public`, `Zava Internal`, `Zava Confidential`, and `Zava Highly Confidential`
   - **Policy scope**: all users and groups
   - **Policy settings**: do not require users to provide a justification; do not require mandatory labeling; do not configure a default label for documents, email, groups, or sites
   - **Policy name**: `Zava Global Label Policy`

3. Create the policy. Completing the wizard publishes it; there is no separate activation action.

4. Return to PowerShell and connect to Security & Compliance PowerShell. Synchronize the labels to Microsoft Entra ID so labels with the groups-and-sites scope can become available to supported containers.

   ```powershell
   Connect-IPPSSession
   Execute-AzureAdLabelSync
   ```

> [!Note] Label and publishing-policy propagation can take up to 24 hours. Propagation is not part of validation in this challenge.

## Task 6: Configure service-side auto-labeling simulation

In this task, you will configure an auto-labeling policy that evaluates content but does not apply labels.

1. In the Microsoft Purview portal, go to **Solutions** > **Information Protection** > **Policies** > **Auto-labeling policies**, and create a policy that **automatically applies a label**.

2. Select **Custom** > **Custom policy**, then enter the policy name `Zava Auto-Label Policy`.

3. Select `Zava Highly Confidential` as the label to auto-apply. Keep the administrative-unit scope at **Full directory**.

4. On the locations page, enable only these supported service-side locations, with all locations included and none excluded:

   - **Exchange email**
   - **SharePoint sites**
   - **OneDrive accounts**

5. Choose **Common rules** and create the rule `Zava High-Risk Identity Data Rule`.

6. Add a **Content contains** condition, select **Sensitive info types**, and configure the group to match **Any of these**:

   - `Credit Card Number`: minimum instance count `5`
   - `U.S. Social Security Number (SSN)`: minimum instance count `5`

   Leave the maximum instance count at **Any** and leave each sensitive information type's default confidence level unchanged.

7. Confirm that the rule is enabled. Do not add an exception and do not enable replacement of a manually applied label.

8. On **Decide if you want to test out the policy now or later**, select **Run policy in simulation mode**.

9. Turn off **Automatically turn on policy if it's not modified for 7 days**. The policy must remain in simulation until an administrator explicitly reviews it and turns it on.

10. Review the summary and create the policy. Confirm the policy appears in the **Simulation** section.

> [!Important] Never select an option that automatically activates this policy after seven days. Simulation results and labeling outcomes are not required for validation.

> [!Important] The workload invariant for any DLP policy or DLP rule that uses a sensitivity-label condition is **Exchange, SharePoint, and OneDrive only**. **Teams must be off**. This prevents unsupported-workload failures. The object created in this task is an auto-labeling policy rather than a DLP policy, and its service-side locations are likewise Exchange, SharePoint, and OneDrive; Teams is not a selected location.

## Task 7: Verify the immediate configuration

In this task, you will inspect the immediate tenant configuration without waiting for label propagation or simulation results.

1. In the Security & Compliance PowerShell session, verify the labels and their order.

   ```powershell
   Get-Label | Where-Object Name -in @(
       "Zava Public",
       "Zava Internal",
       "Zava Confidential",
       "Zava Highly Confidential"
   ) | Sort-Object Priority | Format-Table Name, Priority, ContentType, Disabled -AutoSize
   ```

2. Inspect each complete label configuration. Confirm the scopes, content marking, encryption, internal-only access, and groups-and-sites controls match Task 4.

   ```powershell
   Get-Label -Identity "Zava Public" | Format-List
   Get-Label -Identity "Zava Internal" | Format-List
   Get-Label -Identity "Zava Confidential" | Format-List
   Get-Label -Identity "Zava Highly Confidential" | Format-List
   ```

3. Verify that the publishing policy exists and contains all four labels.

   ```powershell
   Get-LabelPolicy -Identity "Zava Global Label Policy" | Format-List Name, Labels, ExchangeLocation, ModernGroupLocation, Mode
   ```

4. Verify the auto-labeling policy remains in simulation mode and targets the correct label and locations.

   ```powershell
   Get-AutoSensitivityLabelPolicy -Identity "Zava Auto-Label Policy" | Format-List Name, Mode, ApplySensitivityLabel, ExchangeLocation, SharePointLocation, OneDriveLocation
   ```

5. Verify the exact rule name and inspect its sensitive-information condition.

   ```powershell
   Get-AutoSensitivityLabelRule -Identity "Zava High-Risk Identity Data Rule" | Format-List Name, Policy, Disabled, ContentContainsSensitiveInformation
   ```

6. Re-run the three positive prerequisite assertions and confirm each prints `True`:

   ```powershell
   Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
   Connect-ExchangeOnline -ShowBanner:$false
   [bool](Get-AdminAuditLogConfig).UnifiedAuditLogIngestionEnabled
   [bool](Get-SPOTenant).EnableAIPIntegration
   $grpUnifiedSetting = Get-MgBetaDirectorySetting | Where-Object DisplayName -eq "Group.Unified"
   [bool]::Parse(($grpUnifiedSetting.Values | Where-Object Name -eq "EnableMIPLabels").Value)
   ```

<validation step="Validate-Zava-Information-Protection"/>

> [!Important] Validation checks immediate configuration only. It does not grade label propagation, automatic label application, matched-item counts, or simulation results.

## Summary

You positively verified unified auditing, enabled labeling support for SharePoint, OneDrive, Microsoft 365 groups, and sites, created and published the exact Zava sensitivity-label taxonomy, and configured `Zava Auto-Label Policy` with `Zava High-Risk Identity Data Rule` in simulation mode without automatic activation.
