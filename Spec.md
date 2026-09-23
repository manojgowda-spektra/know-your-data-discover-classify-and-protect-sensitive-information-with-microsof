Know Your Data - Discover, Classify and Protect Sensitive Information with Microsoft Purview

Lab Overview
• Cloud: Azure
• Duration: 360 minutes
• Challenges: 4 (Discover sensitive data, Classify with labels and auto-labeling, Endpoint Data Loss Prevention, Insider risk detection for departing users)
• Validations: 4
• Deployed services: Windows 11 Virtual Machine (Standard_B2ms), Network Interface, Virtual Network, Network Security Group, Public IP, StandardSSD_LRS Managed OS Disk, Boot Diagnostics, Custom Script Extension, Existing VM Auto-shutdown Schedule
• Scenario: Zava must identify regulated data, classify it consistently, prevent endpoint exfiltration, and detect risk from departing users. The learner uses a Microsoft 365 E5 tenant and a dedicated Windows 11 lab VM to create Microsoft Purview discovery, sensitivity-labeling, Endpoint DLP, and insider-risk controls. Challenge 4 is cross-checked in the portal and recorded as seven exact tags merged onto the single VM resolved by `DeploymentID`; existing deployment tags including `LabCode` remain unchanged, and no local JSON evidence is used.

This Package Includes

Deliverables Included in the Package
• Lab Guide
• Master Document
• Inline Validations

Inline Validations
Pre-configured inline validations enabled. The four retained paths are `Validations/Validate-Zava-Discovery-Baseline.ps1`, `Validations/Validate-Zava-Information-Protection.ps1`, `Validations/Validate-Zava-Endpoint-DLP.ps1`, and `Validations/Validate-Zava-Departing-Employee-Policy-Evidence.ps1`.

Challenge 4 Evidence and Validator Contract
• Resolve exactly one VM by matching its existing `DeploymentID` tag; never hard-code a resource group.
• Merge `ZavaIRPolicy=Zava Departing Employee Data Theft`, `ZavaIRTemplate=Data theft by departing users`, `ZavaIRPolicyType=Custom policy`, `ZavaIRTrigger=Microsoft Entra account deleted`, `ZavaIRPriorityPages=Both confirmed`, `ZavaIRIndicators=Sharing SharePoint files with people outside the organization;Sharing SharePoint folders with people outside the organization;Downloading content from SharePoint;Sending email with attachments to recipients outside the organization`, and a parseable UTC ISO 8601 `ZavaIREvidenceUtc` recorded after the portal cross-check.
• Never mutate `LabCode` or `DeploymentID`, replace the full tag set, or create local JSON evidence. Azure `Update-AzTag -Operation Merge` preserves existing tags.
• Microsoft 365 validators use exactly `M365_VALIDATOR_APP_ID`, `M365_VALIDATOR_ORGANIZATION`, and `M365_VALIDATOR_CERT_THUMBPRINT`, with the certificate in the Windows validation account's `CurrentUser\My` store. No tenant ID, base64 PFX, PFX password, or SharePoint Online URL is a required contract variable, and no interactive fallback is permitted.

Operational Scope
• Assign the deployment identity at the deployment scope required by ARM. Separately assign the learner's tag-capable role at the single VM scope.
• Resources can remain provisioned for at least 24 hours while the VM is deallocated outside explicit onboarding, synchronization, telemetry, and release windows.
• For each such window: start the VM and verify guest reachability; perform onboarding, sync, telemetry, or release checks; confirm Purview health and current connectivity; deallocate when complete and verify `PowerState/deallocated`; start and recheck before learner release. The `Microsoft.DevTestLab/schedules` auto-shutdown resource is deployed with status `Disabled`, so it cannot stop the VM during the pre-deployment warm-up window.
• Microsoft Learn alignment covers certificate-based app-only Exchange/Security & Compliance PowerShell, `Update-AzTag` merge semantics, `Microsoft.DevTestLab/schedules`, and Azure Policy's built-in managed-disk definitions.

Lab Guide Preview
Preview link for the lab guide documentation:
[\[CloudLabs LabGuide Preview\]](https://experience.cloudlabs.ai/#labguidepreview/<GUID>/1)

Lab Environment Setup & Deployment
Lab provisioning and setup include one or more of the following components:
• ARM template deployment
• Custom Script Extension (CSE)
• Custom image-based environment setup
• Supporting deployment configurations as required

Exclusions
This package does not include:
• Scoring or grading mechanisms for inline validations
• Complex or advanced inline question types