# Challenge 03: Endpoint Data Loss Prevention

### Estimated Duration: 60 minutes

## Scenario

Zava is designing endpoint controls ahead of rolling out managed devices. In this challenge, you will establish why Endpoint DLP depends on an onboarded device, then build the three policies that will protect sensitive identity and payment data from removable-media transfer, unsanctioned cloud upload, and sharing with generative-AI websites once devices are onboarded. You will work in CloudLabs deployment **Zava-<inject key="DeploymentID" enableCopy="false"/>**.

## Overview

You will create three Microsoft Purview Data Loss Prevention policies scoped only to **Devices**. Every rule will use a sensitive-information condition and an enforcing **Block** action. Because this tenant has no onboarded device, the policies are assessed on their configuration rather than on an observed block.

## Objectives

- Task 1: Confirm the endpoint enforcement dependency
- Task 2: Block sensitive data copied to removable storage
- Task 3: Define unsanctioned cloud destinations
- Task 4: Block sensitive uploads to unsanctioned cloud storage
- Task 5: Block sensitive sharing with generative-AI websites and interpret evidence
- Task 6: Validate the immediate configuration

## Task 1: Confirm the endpoint enforcement dependency

In this task, you will establish what Endpoint DLP requires before it can enforce anything, and confirm the current state of this lab tenant. This is an observation task, not an onboarding task.

1. On the Windows lab VM, open Microsoft Edge and browse to <https://purview.microsoft.com>.
2. If prompted, sign in with the lab identity:
   - Username: <inject key="AzureAdUserEmail"></inject>
   - Temporary Access Pass: <inject key="AzureAdUserPassword"></inject>
3. In the Microsoft Purview portal, open **Settings** > **Device onboarding** > **Devices**.
4. Confirm that **no devices are listed**. This lab tenant has no onboarded device.
5. Read the banner Microsoft displays on the endpoint settings pages. It states that cloud service, cloud storage, generative AI, and device indicators require onboarded devices.
6. Record, in your own words, why the policies you are about to build cannot block anything in this environment. Microsoft Purview Endpoint DLP has no agent of its own; it enforces through the Microsoft Defender for Endpoint sensor on an onboarded device. With no onboarded device there is no sensor to carry the policy, so no activity can be intercepted.

> [!IMPORTANT]
> Do not download an onboarding package, run onboarding commands, or change Defender settings. Device onboarding is an operator responsibility and is deliberately out of scope for this challenge.

> [!NOTE]
> This challenge is assessed on the configuration you build, not on observing a block. That is the same distinction a real deployment faces: the policy design is complete and correct long before the estate is fully onboarded, and a policy that is correctly configured will begin enforcing the moment a device is onboarded.

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

1. Open **Data loss prevention** > **Settings** (gear icon in the upper-left corner) > **Data Loss Prevention** > **Endpoint DLP settings** > **Browser and domain restrictions to sensitive data**.
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
9. Reopen each of the three policies you created and confirm its configuration is complete: the policy name, the **Devices**-only location, the rule name, the sensitive-information condition, the **Block** action, and the policy tip. This configuration review is the deliverable for this challenge.
10. Record which browser each control would apply to once a device is onboarded. Microsoft Edge supports these endpoint actions natively; Chrome and Firefox require the Microsoft Purview extension. This matters for rollout planning even though no block can occur here.
11. Open **Data Loss Prevention** > **Activity explorer** and filter by the three Zava policy or rule names. Confirm that **no endpoint events are present**, and explain in one sentence why that is the expected and correct result in a tenant with no onboarded device. An empty Activity explorer here is evidence of the dependency, not evidence of a misconfigured policy.
12. Record your interpretation in a local text note:
    - `Zava Block Removable Storage` reduces loss through portable media.
    - `Zava Block Unsanctioned Cloud Uploads` reduces exfiltration to `dropbox.com`, `drive.google.com`, and `box.com`.
    - `Zava Block Generative AI Sharing` reduces disclosure through file upload or paste to destinations in `Generative AI Websites`.

> [!NOTE]
> No endpoint policy tip, block, or Activity explorer event can appear in this tenant, because no device is onboarded to carry the policy. That is expected. The three policies are complete and correct as configured, and each will begin enforcing as soon as a device is onboarded. Do not weaken, recreate, or re-scope a policy because no event appeared.

## Task 6: Validate the immediate configuration

In this task, you will validate only the configuration state that can be checked immediately.

1. Review the three policy summaries one final time. Confirm exact policy and rule names, **Devices** as the only location, the either-sensitive-information-type condition, and the required **Block** actions.
2. Confirm that `Zava Unsanctioned Cloud Storage` contains exactly `dropbox.com`, `drive.google.com`, and `box.com`, and that the generative-AI rule references the built-in `Generative AI Websites` group.
3. Run the validation below. Policy synchronization, policy-tip display, blocked-test outcomes, and Activity explorer event arrival are deliberately not graded.

<validation step="Validate-Zava-Endpoint-DLP"/>

## Summary

You established why Endpoint DLP depends on an onboarded device and created three enforcing Endpoint DLP policies. The policies use content inspection to block sensitive removable-media copies, uploads to Zava's exact unsanctioned domains, and uploads or paste actions to Microsoft's built-in generative-AI website group. Each is complete and correct as configured and will begin enforcing as soon as a device is onboarded. You also distinguished a configuration deliverable from enforcement evidence that this tenant cannot produce.