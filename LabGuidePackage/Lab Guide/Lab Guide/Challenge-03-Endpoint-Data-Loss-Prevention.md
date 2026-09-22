# Challenge 03: Endpoint Data Loss Prevention

### Estimated Duration: 60 minutes

## Scenario

Zava needs enforceable controls on its managed Windows 11 endpoint. In this challenge, you will confirm that the lab operator's pre-onboarding work is healthy, then protect sensitive identity and payment data from removable-media transfer, unsanctioned cloud upload, and sharing with generative-AI websites. You will work in CloudLabs deployment **Zava-<inject key="DeploymentID" enableCopy="false"/>**.

## Overview

You will create three Microsoft Purview Data Loss Prevention policies scoped only to **Devices**. Every rule will use a sensitive-information condition and an enforcing **Block** action. You will then use Microsoft Edge to attempt a controlled action with synthetic data and review any available endpoint evidence.

## Objectives

- Task 1: Verify endpoint onboarding, connectivity, health, and readiness
- Task 2: Block sensitive data copied to removable storage
- Task 3: Define unsanctioned cloud destinations
- Task 4: Block sensitive uploads to unsanctioned cloud storage
- Task 5: Block sensitive sharing with generative-AI websites and interpret evidence
- Task 6: Validate the immediate configuration

## Task 1: Verify endpoint onboarding, connectivity, health, and readiness

In this task, you will positively confirm that the operator-prepared VM can receive and enforce Endpoint DLP policy. This is a prerequisite check, not an onboarding task.

1. On the Windows 11 lab VM, open Microsoft Edge and browse to <https://purview.microsoft.com>.
2. If prompted, sign in with the lab identity:
   - Username: <inject key="AzureAdUserEmail"></inject>
   - Temporary Access Pass: <inject key="AzureAdUserPassword"></inject>
3. In the Microsoft Purview portal, open **Settings** > **Device onboarding** > **Devices**. Identify this VM by running `hostname` in Windows Terminal and matching the returned computer name to the device record.
4. Open the device record and positively verify all of the following:
   - The VM appears as an onboarded device and **Endpoint DLP status** is enabled.
   - **Last seen** shows recent connectivity. For this challenge, require a timestamp within the past 24 hours.
   - **Configuration status** is **Updated**. This means the health parameters are enabled, correctly configured, and sending the expected heartbeat to Microsoft Purview.
   - If **Policy sync status** is present, it is **Updated**. Before any endpoint policy exists, **Not available** can be expected; it does not by itself prove a failed onboarding.
5. Open **Settings** > **Device onboarding** > **Device report**. In **Device onboarding**, confirm that the VM is running Endpoint DLP without a configuration issue. In **Device readiness to receive policy updates**, confirm that the VM is not identified as at risk because it was offline in the past day, has an outdated Defender version, or has a configuration issue.
6. In **Device readiness for feature**, confirm that the VM is ready for **Paste to supported browsers**, which is required later in this challenge.

> [!IMPORTANT]
> If the device is missing, Endpoint DLP is disabled, **Last seen** is older than 24 hours, **Configuration status** is not **Updated**, the device is shown as not ready to receive policy updates, or paste readiness is not healthy, **stop now and contact the lab operator**. Do not download an onboarding package, run onboarding commands, change Defender settings, or attempt remediation. Endpoint onboarding and health are operator responsibilities.

> [!NOTE]
> The device report refreshes approximately hourly. Its policy-readiness indicator identifies devices at risk of missing future updates; it does not assert that a particular update already failed.

## Task 2: Block sensitive data copied to removable storage

In this task, you will create an enforcing, Devices-only policy with an explicit sensitive-information condition.

1. In Microsoft Purview, open **Solutions** > **Data Loss Prevention** > **Policies**, select **Create policy**, and choose **Enterprise applications & devices** > **Custom** > **Custom policy**.
2. Name the policy `Zava Block Removable Storage`, retain **Full directory** for administrative units, and continue to location selection.
3. Enable only **Devices**. Turn off every other location, including Exchange email, SharePoint sites, OneDrive accounts, Teams chat and channel messages, on-premises repositories, and Microsoft 365 Copilot. Keep all users, groups, devices, and device groups in scope.
4. Select **Create or customize advanced DLP rules** and create the rule `Zava Block Sensitive Data to Removable Storage Rule`.
5. Under **Conditions**, add **Content contains** and add both of these sensitive information types to the same condition group:
   - `Credit Card Number`
   - `U.S. Social Security Number`

   Keep the group logic as **Any of these**, so either sensitive information type can satisfy the rule. Do not create an endpoint rule without this content condition.
6. Under **Actions**, add **Audit or restrict activities on devices**. For **File activities for all apps**, apply restrictions to specific activity and set **Copy to a removable USB device** to **Block**.
7. Turn on user notifications and policy tips for the person performing the restricted activity. Save the rule.
8. On **Policy mode**, select **Turn the policy on immediately**, review that the location is only **Devices**, and submit the policy.

> [!TIP]
> A removable USB device group is unnecessary here because Zava is blocking this action for all removable storage. Do not create a restricted app group; app groups control a different endpoint concept.

## Task 3: Define unsanctioned cloud destinations

In this task, you will create the exact custom sensitive service domain group used by the upload policy.

1. Open **Data loss prevention** > **Settings** (gear icon in the upper-left corner) > **Data Loss Prevention** > **Endpoint settings** > **Browser and domain restrictions to sensitive data**.
2. Set **Service domains** to **Block**. Add the following cloud service domains to the blocked service-domain list, using host names only and no protocol, path, trailing period, or wildcard:
   - `dropbox.com`
   - `drive.google.com`
   - `box.com`
3. Under **Sensitive service domain groups**, select **Create sensitive service domain group** and name it `Zava Unsanctioned Cloud Storage`.
4. Add exactly the same three entries with **Match type** set to **URL**:
   - `dropbox.com`
   - `drive.google.com`
   - `box.com`
5. Save the group and verify that it contains exactly three URL entries.

> [!IMPORTANT]
> A **Sensitive service domain group** is a website-destination group used by service-domain and browser actions. It is not a **Restricted app**, **Restricted app group**, or removable USB device group.

## Task 4: Block sensitive uploads to unsanctioned cloud storage

In this task, you will associate the custom destination group with a content-aware blocking rule.

1. Return to **Data Loss Prevention** > **Policies** and create a custom policy named `Zava Block Unsanctioned Cloud Uploads`.
2. Retain **Full directory**, enable only **Devices**, turn off every other location, and keep all users, groups, devices, and device groups in scope.
3. Choose **Create or customize advanced DLP rules** and create `Zava Block Sensitive Uploads to Unsanctioned Cloud Rule`.
4. Add a **Content contains** condition with `Credit Card Number` and `U.S. Social Security Number` in one **Any of these** group. Either sensitive information type must be sufficient to match.
5. Add **Audit or restrict activities on devices**. Under **Service domain and browser activities**, set **Upload to a restricted cloud service domain or access from an unallowed browser** to **Block**.
6. Choose different restrictions for sensitive service domains, add `Zava Unsanctioned Cloud Storage`, and ensure its upload restriction is **Block**.
7. Turn on user notifications and policy tips, save the rule, choose **Turn the policy on immediately**, and submit the policy.
8. Review the policy summary and confirm its only location is **Devices**, its rule contains the two named sensitive information types, and the exact custom domain group is referenced.

## Task 5: Block sensitive sharing with generative-AI websites and interpret evidence

In this task, you will use Microsoft's built-in, non-editable destination group and perform a controlled endpoint test in Microsoft Edge.

1. Create another custom DLP policy named `Zava Block Generative AI Sharing`. Retain **Full directory**, enable only **Devices**, turn off every other location, and keep all users, groups, devices, and device groups in scope.
2. Select **Create or customize advanced DLP rules** and create `Zava Block Sensitive Data to Generative AI Rule`.
3. Add a **Content contains** condition with `Credit Card Number` and `U.S. Social Security Number` in one **Any of these** group. Do not omit this sensitive-information condition.
4. Add **Audit or restrict activities on devices**. Under **Service domain and browser activities**, configure both actions as **Block**:
   - **Upload to a restricted cloud service domain or access from an unallowed browser**
   - **Paste to supported browsers**
5. For each action, choose different restrictions for sensitive service domains and select the built-in `Generative AI Websites` group. Do not create a replacement group and do not attempt to edit or delete the built-in group.
6. Turn on user notifications and policy tips. Save the rule, choose **Turn the policy on immediately**, and submit the policy.
7. In Notepad, create `%USERPROFILE%\Documents\Zava-Endpoint-Sensitive-Data.txt`. Add clearly labeled synthetic payment and identity records using the non-live values that you already proved match `Credit Card Number` or `U.S. Social Security Number` in Challenge 01. Save and close the file so Endpoint DLP can classify it.
8. Allow time for the newly enabled policies to synchronize. Keep the VM online. Return to **Settings** > **Device onboarding** > **Devices**, open the VM, and note **Last policy sync time** and **Policy sync status**. A new policy can take time to synchronize, and the devices list can take up to two hours to reflect the latest status.
9. Use the operator-provided removable-storage test device or approved removable-media emulation to attempt to copy `Zava-Endpoint-Sensitive-Data.txt`. If the new policy has synchronized, confirm that the copy is blocked and observe the policy tip. Do not change the action to allow an override.
10. In Microsoft Edge, use an operator-approved test destination represented by `Zava Unsanctioned Cloud Storage` or `Generative AI Websites` to attempt an upload of the file. Where a text prompt is available, also attempt to paste only the synthetic test text. Observe whether the action is blocked and whether a policy tip appears. Do not use Chrome or Firefox for this challenge; those browsers require the Microsoft Purview extension, while Edge supports these endpoint actions natively.
11. Open **Data Loss Prevention** > **Activity explorer**. If events are available, filter by the VM, recent activity time, and the three Zava policy or rule names. Correlate each available event with its attempted activity and outcome.
12. Record your interpretation in a local text note:
    - `Zava Block Removable Storage` reduces loss through portable media.
    - `Zava Block Unsanctioned Cloud Uploads` reduces exfiltration to `dropbox.com`, `drive.google.com`, and `box.com`.
    - `Zava Block Generative AI Sharing` reduces disclosure through file upload or paste to destinations in `Generative AI Websites`.

> [!NOTE]
> Policy synchronization, endpoint policy tips, classification responses, and Activity explorer telemetry can be delayed. The paste action can also show a brief classification delay before Edge completes policy evaluation. These observations are instructional evidence only and are not inputs to the graded validator. Do not weaken or recreate a policy merely because an event or tip has not appeared yet.

## Task 6: Validate the immediate configuration

In this task, you will validate only the configuration state that can be checked immediately.

1. Review the three policy summaries one final time. Confirm exact policy and rule names, **Devices** as the only location, the either-sensitive-information-type condition, and the required **Block** actions.
2. Confirm that `Zava Unsanctioned Cloud Storage` contains exactly `dropbox.com`, `drive.google.com`, and `box.com`, and that the generative-AI rule references the built-in `Generative AI Websites` group.
3. Run the validation below. Policy synchronization, policy-tip display, blocked-test outcomes, and Activity explorer event arrival are deliberately not graded.

<validation step="Validate-Zava-Endpoint-DLP"/>

## Summary

You verified the health of Zava's pre-onboarded Windows endpoint and created three enforcing Endpoint DLP policies. The policies use content inspection to block sensitive removable-media copies, uploads to Zava's exact unsanctioned domains, and uploads or paste actions to Microsoft's built-in generative-AI website group. You also distinguished immediate configuration validation from delayed endpoint and reporting evidence.