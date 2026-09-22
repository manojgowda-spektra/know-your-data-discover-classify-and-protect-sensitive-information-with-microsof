# Challenge 04: Insider Risk Detection for Departing Users

### Estimated Duration: 45 Minutes

## Scenario

Zava needs a repeatable way to identify possible data theft around employee departures. Because Zava has no HR connector in this lab tenant, you will use Microsoft Entra account deletion as the event that brings a departing user into policy scope. You will configure only the required indicators, create a custom policy, and record non-secret evidence for validation.

## Overview

In this challenge, you will distinguish globally enabled indicators from indicators selected in a policy, enable four Office indicators, create the custom policy `Zava Departing Employee Data Theft` from the `Data theft by departing users` template, complete both content-priority stages, and record cloud-visible evidence as tags on the existing Azure lab VM.

## Objectives

- Task 1: Enable the four required global indicators
- Task 2: Create the custom departing-user policy
- Task 3: Complete both content-priority stages and preserve policy indicators
- Task 4: Cross-check the policy and record evidence on the Azure lab VM
- Task 5: Interpret the expected empty alerts queue and validate the evidence

## Task 1: Enable the four required global indicators

In this task, you will make the required built-in indicators available to Insider Risk Management policies. A global settings indicator controls whether its signal is collected and available for policy configuration. A policy indicator is a globally enabled indicator selected in one policy; it contributes to risk scoring only for an in-scope user after that policy's triggering event occurs.

1. In Microsoft Edge, open <https://purview.microsoft.com>, then open **Solutions** > **Insider Risk Management**.
2. Open **Settings** > **Policy indicators** and remain on the **Built-in indicators** tab.
3. Expand **Office indicators** and enable exactly these four current indicators:
   - **Sharing SharePoint files with people outside the organization**
   - **Sharing SharePoint folders with people outside the organization**
   - **Downloading content from SharePoint**
   - **Sending email with attachments to recipients outside the organization**
4. Preserve any indicators that were already enabled. Do not disable unrelated tenant settings merely to make the page contain only four selections.
5. Select **Save** and wait for the success notification.
6. Reopen **Policy indicators**, expand **Office indicators**, and confirm that all four named indicators remain enabled.

> [!Important] Enabling an indicator globally does not add it automatically to every policy and does not, by itself, assign a risk score or generate an alert. You will select the same four indicators in `Zava Departing Employee Data Theft`.

## Task 2: Create the custom departing-user policy

In this task, you will start the full custom-policy workflow rather than accepting the settings of a quick policy.

1. In **Insider Risk Management**, open **Policies**.
2. Select **Create policy** > **Custom policy**. Do not select **Quick policy**.
3. On **Policy template**, select **Data theft by departing users**, review its prerequisites and detected activities, and continue.
4. Enter the policy name `Zava Departing Employee Data Theft`. Add a description stating that the policy detects possible data theft associated with departing users at Zava.
5. If an **Admin units** page appears, do not add an administrative unit; continue to the tenant-wide scope page.
6. On **Users and groups**, select **Include all users and groups**. Do not exclude any users or groups.
7. On the departure trigger page, select **User account deleted from Microsoft Entra**.
8. Do not select an HR connector trigger. No HR connector exists in this lab tenant, and the `Data theft by departing users` template supports Microsoft Entra account deletion as its departure trigger.

> [!Note] A Microsoft Entra account deletion is a triggering event, not one of the four Office policy indicators. The trigger brings a user into scope; selected policy indicators then contribute to risk scoring for that user.

## Task 3: Complete both content-priority stages and preserve policy indicators

In this task, you will complete the content-priority choice and its detail stage, then select the four indicators in the policy.

1. On the first **Content to prioritize** stage, select **I want to prioritize content** and continue.
2. On the following content-priority detail stage, add the sensitivity label `Zava Highly Confidential` as priority content. Leave other priority-content categories unconfigured.
3. On the scoring choice in the content-priority detail stage, select **Get alerts for all activity**. This keeps all qualifying policy activity eligible for scoring while increasing the importance of activity involving `Zava Highly Confidential` content.
4. Continue to **Policy indicators**. Under **Office indicators**, select exactly these four indicators for this policy:
   - **Sharing SharePoint files with people outside the organization**
   - **Sharing SharePoint folders with people outside the organization**
   - **Downloading content from SharePoint**
   - **Sending email with attachments to recipients outside the organization**
5. Keep the four Office indicators selected as you continue through sequence detection, cumulative exfiltration detection, risk score boosters, and indicator-threshold pages. Accept the Microsoft-provided defaults on those pages; do not replace the four required indicators.
6. On the indicator-threshold page, select **Use default thresholds for all indicators**.
7. Stop on **Review** and compare the summary with this required configuration:

   | Setting | Required value |
   |---|---|
   | Policy name | `Zava Departing Employee Data Theft` |
   | Policy creation choice | `Custom policy` |
   | Template | `Data theft by departing users` |
   | Users and groups | Include all users and groups |
   | Trigger | `User account deleted from Microsoft Entra` |
   | First content-priority stage | I want to prioritize content |
   | Content-priority detail stage | `Zava Highly Confidential`; get alerts for all activity |
   | Office policy indicators | All four required indicators |
   | Indicator thresholds | Use default thresholds for all indicators |

8. Correct any mismatch with **Edit**, return to **Review**, and select **Submit**.
9. Return to **Policies** and confirm that `Zava Departing Employee Data Theft` appears in the user-policy list.

## Task 4: Cross-check the policy and record evidence on the Azure lab VM

In this task, you will perform a guided portal cross-check and merge a compact, non-secret seven-tag evidence set onto the already deployed Azure VM. The evidence is cloud-visible and does not depend on a local file.

1. On **Policies**, select `Zava Departing Employee Data Theft` and review its details. If needed, select **Edit policy** and advance through the workflow without changing settings.
2. Cross-check all of the following in the portal:
   - The template is **Data theft by departing users**.
   - The policy was created with the custom-policy workflow.
   - The trigger is **User account deleted from Microsoft Entra**.
   - The first **Content to prioritize** stage was completed.
   - The content-priority detail stage prioritizes `Zava Highly Confidential` and scores all activity.
   - The policy contains all four required Office indicators.
3. Close the details or editing workflow without submitting changes after the cross-check.
4. On the VM, open **Windows PowerShell**. Run the commands below. They fail clearly if no authenticated Azure context exists. Compare the displayed account, tenant, subscription name, and subscription ID with the lab context shown in the Azure portal, and type `YES` only after confirming that the active context is the lab context. When prompted, paste deployment ID <inject key="DeploymentID"></inject>. The commands derive the subscription ID from the confirmed active context and resolve the **lab VM for deployment <inject key="DeploymentID" enableCopy="false"></inject>** by its existing `DeploymentID` tag; no resource-group name is assumed.

   ```powershell
   $context = Get-AzContext
   if (-not $context -or -not $context.Account -or -not $context.Subscription -or
       [string]::IsNullOrWhiteSpace([string]$context.Subscription.Id)) {
       throw 'No authenticated Azure context was found. Run Connect-AzAccount, select the lab context, and retry.'
   }

   $context | Select-Object `
       @{Name='Account';Expression={$_.Account.Id}}, `
       @{Name='TenantId';Expression={$_.Tenant.Id}}, `
       @{Name='SubscriptionName';Expression={$_.Subscription.Name}}, `
       @{Name='SubscriptionId';Expression={$_.Subscription.Id}} | Format-List

   $subscriptionId = (Get-AzContext).Subscription.Id
   $contextConfirmed = Read-Host 'After comparing this output with the lab context in the Azure portal, type YES to continue'
   if ($contextConfirmed -cne 'YES') {
       throw 'The active Azure context was not confirmed as the lab context. Select the correct context and retry.'
   }

   $deploymentId = Read-Host 'Paste the lab deployment ID'
   $vms = @(
       Get-AzVM -ErrorAction Stop |
           Where-Object { $_.Tags -and $_.Tags['DeploymentID'] -eq $deploymentId }
   )

   if ($vms.Count -ne 1) {
       throw "Expected exactly one VM tagged DeploymentID=$deploymentId in subscription $subscriptionId; found $($vms.Count)."
   }
   $vm = $vms[0]
   $vm | Select-Object Name, ResourceGroupName, Id
   ```

5. After verifying that exactly one VM was resolved, use this exact canonical seven-tag schema. The UTC timestamp is created now, after the portal cross-check. `Update-AzTag` with `Merge` adds or updates only these evidence tags and preserves all existing tags, including `DeploymentID`, `ODLID`, `LabCode`, `LabName`, and `Environment`.

   ```powershell
   $evidenceTags = @{
       'ZavaIRPolicy'        = 'Zava Departing Employee Data Theft'
       'ZavaIRTemplate'      = 'Data theft by departing users'
       'ZavaIRPolicyType'    = 'Custom policy'
       'ZavaIRTrigger'       = 'Microsoft Entra account deleted'
       'ZavaIRPriorityPages' = 'Both confirmed'
       'ZavaIRIndicators'    = 'Sharing SharePoint files with people outside the organization;Sharing SharePoint folders with people outside the organization;Downloading content from SharePoint;Sending email with attachments to recipients outside the organization'
       'ZavaIREvidenceUtc'   = [DateTime]::UtcNow.ToString('o')
   }

   Update-AzTag -ResourceId $vm.Id -Tag $evidenceTags -Operation Merge -ErrorAction Stop | Out-Null
   ```

6. Re-read the VM and verify the seven `ZavaIR*` tags and their exact values. Confirm that the existing `DeploymentID`, `ODLID`, `LabCode`, `LabName`, and `Environment` tags remain unchanged.

   ```powershell
   $updatedVm = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -ErrorAction Stop
   $updatedVm.Tags.GetEnumerator() |
       Sort-Object Key |
       Format-Table Key, Value -AutoSize
   ```

> [!Important] Do not use `New-AzTag` or the `Replace` operation because either can replace the complete tag set. Do not place passwords, access tokens, Temporary Access Pass values, personal data, user content, or alert details in Azure tags.

## Task 5: Interpret the expected empty alerts queue and validate the evidence

In this task, you will explain why policy creation does not immediately create an alert, then validate the cloud-visible VM tags.

1. Open the **Alerts** dashboard in Insider Risk Management and observe its current state. An empty queue is expected in this lab.
2. Confirm your understanding: an alert requires a user in policy scope to have the configured triggering event, matching activity for selected indicators, and a resulting risk score that meets the alert threshold. Creating the policy alone meets none of those alert-generation conditions.
3. Do not delete a Microsoft Entra user to manufacture a trigger, do not generate synthetic insider-risk activity, and do not wait for an alert. Alert generation and delayed telemetry are not validation requirements.
4. Select the validation below. It checks the exact seven evidence tags on the deployed Azure VM: policy, template, policy type, trigger, both priority pages, the four indicators in their required order, and the UTC evidence timestamp created after the portal cross-check. It does not use alert state as proof of success.
<validation step="Validate-Zava-Departing-Employee-Policy-Evidence"/>

## Summary

You enabled four global Office indicators, selected those same indicators in the custom `Zava Departing Employee Data Theft` policy, used the Microsoft Entra account-deleted trigger, completed both content-priority stages, and recorded the exact seven-tag portal-verified evidence contract on the existing Azure lab VM by using a merge operation that preserved its deployment and lab tags. You also established why an empty alerts queue is the correct result when no qualifying departure trigger and scored activity have occurred.

You have successfully completed the Hands-on Lab / Hackathon.