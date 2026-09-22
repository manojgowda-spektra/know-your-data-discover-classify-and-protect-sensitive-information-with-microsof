# Challenge 01: Discover Sensitive Data

### Estimated Duration: 55 minutes

## Scenario

Zava needs an initial view of regulated information before it introduces user-facing restrictions. You will verify two built-in Microsoft Purview classifiers, create controlled synthetic content, distribute that content across SharePoint and OneDrive, and configure a discovery-only data loss prevention policy.

## Overview

This challenge establishes a Microsoft Purview Data Loss Prevention baseline for sensitive payment and identity data. The policy will run in simulation mode, so it can identify matching content without enforcing rule actions. Only the immediate policy configuration is validated; delayed simulation results and Content Explorer counts are not graded.

## Objectives

- Task 1: Create controlled synthetic documents
- Task 2: Test the built-in sensitive information types
- Task 3: Place the documents across SharePoint and OneDrive
- Task 4: Configure and validate the discovery baseline

## Task 1: Create controlled synthetic documents

In this task, you will create three Word documents containing fictitious values suitable for classifier testing. Do not add real personal, employee, customer, or payment information.

1. On the lab VM, open Microsoft Edge and sign in to <https://www.microsoft365.com> with the following credentials:

   - **Username:** <inject key="AzureAdUserEmail"></inject>
   - **Temporary Access Pass:** <inject key="AzureAdUserPassword"></inject>

2. Open **OneDrive**, create a folder named **Zava Discovery Documents**, and confirm that the folder opens successfully.

3. Use Word for the web to create **Zava-Customer-Payments.docx** in that folder. Add a heading that identifies the content as synthetic training data, followed by a fictitious cardholder name, the field label **Credit card number**, the non-live test value **4532 0151 1283 0366**, and the expiration date **12/2032**. Save and close the document.

4. Create **Zava-Employee-Records.docx** in the same folder. Add a heading that identifies the content as synthetic training data, followed by a fictitious employee name, the field label **Social Security Number**, and the non-live test value **078-05-1120**. Save and close the document.

5. Create **Zava-Mixed-Sensitive-Data.docx** in the same folder. Include the same synthetic-data notice and both labeled test records from the preceding two steps. Save and close the document.

6. Download the three documents to **C:\Users\Public\Documents\ZavaDiscovery**. Create the local folder first if it does not exist, and verify that all three `.docx` files are present.

> [!Important] The values in this challenge are fictitious and are used only in the disposable lab tenant. Never substitute live regulated data.

## Task 2: Test the built-in sensitive information types

In this task, you will verify how the built-in classifiers respond to the controlled files before using those classifiers in a policy.

1. In Microsoft Edge, open the [Microsoft Purview portal](https://purview.microsoft.com), then open **Information Protection** > **Classifiers** > **Sensitive info types**.

2. Search for and open **Credit Card Number**. Select **Test**, upload **C:\Users\Public\Documents\ZavaDiscovery\Zava-Customer-Payments.docx**, start the test, and review the match result before finishing the test.

3. Search for and open **U.S. Social Security Number**. Select **Test**, upload **C:\Users\Public\Documents\ZavaDiscovery\Zava-Employee-Records.docx**, start the test, and review the match result before finishing the test.

4. Record the detected type, confidence, and match count for each test in a new text file named **Classifier-Test-Notes.txt** under **C:\Users\Public\Documents\ZavaDiscovery**. If a test does not match, confirm that the document contains its field label and formatted value, save the document, and repeat the test once.

> [!Note] The portal tests one unencrypted file at a time. A successful file test confirms classifier behavior against that file; it does not prove that a tenant-wide simulation scan has completed.

## Task 3: Place the documents across SharePoint and OneDrive

In this task, you will distribute the controlled documents between the two Microsoft 365 workloads that the policy will inspect.

1. From the Microsoft 365 app launcher, open **SharePoint**, create a private team site named **Zava Discovery Site**, and wait until its **Documents** library is available.

2. Upload **Zava-Customer-Payments.docx** and **Zava-Mixed-Sensitive-Data.docx** from **C:\Users\Public\Documents\ZavaDiscovery** to the SharePoint site's **Documents** library. Confirm that both file names appear in the library.

3. Return to OneDrive and confirm that **Zava-Employee-Records.docx** remains in **Zava Discovery Documents**.

4. Delete the OneDrive copies of **Zava-Customer-Payments.docx** and **Zava-Mixed-Sensitive-Data.docx** so the final evidence set consists of two documents in SharePoint and one document in OneDrive.

5. Open one SharePoint document and the OneDrive document to confirm that the uploads are readable and retain their synthetic values.

> [!Note] SharePoint and OneDrive indexing, classifier aggregation, and simulation reporting are asynchronous. Do not wait for Content Explorer counts or policy matches before continuing.

## Task 4: Configure and validate the discovery baseline

In this task, you will create a custom advanced DLP policy that inspects only SharePoint and OneDrive and remains non-enforcing.

1. In the Microsoft Purview portal, open **Data Loss Prevention** > **Policies**, start a new policy, and select the **Custom** category and **Custom policy** template.

2. Name the policy **Zava Discovery Baseline**, retain the **Full directory** administrative scope, and provide a description stating that the policy discovers synthetic payment and identity data without enforcement.

3. On the locations page, leave only **SharePoint sites** and **OneDrive accounts** enabled. Turn off Exchange email, Teams chat and channel messages, Devices, On-premises repositories, and Fabric and Power BI workspaces. Keep all SharePoint sites and all OneDrive accounts included.

4. Select **Create or customize advanced DLP rules**, then create a rule named **Zava Discovery Sensitive Data Rule**.

5. Add a **Content contains** condition, select **Sensitive info types**, and add **Credit Card Number** and **U.S. Social Security Number** to the same condition group. Configure the group to match **Any of these**, so either sensitive information type satisfies the condition. Retain the default instance count and confidence settings, leave restrictive actions unconfigured, turn off user notifications, and save the rule.

6. On **Simulate or turn on the policy**, select **Run the policy in simulation mode**. Do not enable policy tips, and clear any option that would automatically turn on the policy after the simulation period.

7. Review the configuration and confirm all of the following before submitting it:

   - The policy name and rule name exactly match the names specified in this challenge.
   - SharePoint sites and OneDrive accounts are the only enabled locations.
   - Either of the two selected sensitive information types can satisfy the content condition.
   - The selected mode is simulation, not enforcement.

8. Submit the policy, return to the policy list, and confirm that its status is **In simulation**. Do not wait for the simulation dashboard to populate.

9. Run the automated configuration check below. The check evaluates immediate policy and rule settings only; it does not grade document indexing, Content Explorer counts, simulation matches, or alerts.

<validation step="Validate-Zava-Discovery-Baseline"/>

> [!Tip] Simulation mode evaluates a policy without applying its enforcement actions. SharePoint and OneDrive simulation scans can remain **In progress** while existing and newly uploaded content is evaluated, so delayed results are not a completion requirement.

## Summary

You created synthetic payment and identity documents, tested two built-in Microsoft Purview sensitive information types, distributed the documents across SharePoint and OneDrive, and configured a discovery-only DLP policy in simulation mode. Zava now has an immediate, verifiable policy baseline without depending on delayed scan results.