using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
# Every Microsoft 365 tenant validator uses exactly this operator-managed,
# certificate-only contract:
#   M365_VALIDATOR_APP_ID              Microsoft Entra application (client) ID
#   M365_VALIDATOR_ORGANIZATION         Primary tenant *.onmicrosoft.com domain
#   M365_VALIDATOR_CERT_THUMBPRINT      Certificate in CurrentUser\My
# The app requires admin-consented Exchange.ManageAsApp application permission
# for both Office 365 Exchange Online and Microsoft Exchange Online Protection,
# service-principal RBAC that permits the Exchange and Purview read cmdlets below,
# Microsoft Graph GroupSettings.Read.All application permission, and SharePoint
# app-only authorization sufficient to run Get-SPOTenant. No TAP, user password,
# client secret, interactive/device-code flow, or PSCredential is supported.
$scope = "subscription '$sub' (deployment '$DID')"
$count = 0
$found = $false

function Test-TrueValue {
    param([object]$Value)
    if ($Value -is [bool]) { return $Value }
    return ("$Value" -ieq 'True')
}

function Test-EnabledLocation {
    param([object]$Value)
    $values = @($Value) | ForEach-Object { if ($null -ne $_) { "$($_)".Trim() } }
    return (@($values | Where-Object { $_ -and $_ -notin @('None', '{}', '[]') }).Count -gt 0)
}

function Test-AllLocation {
    param([object]$Value)
    return (@($Value) | ForEach-Object { "$_".Trim() }) -icontains 'All'
}

function Test-ExactSet {
    param([object]$Actual, [string[]]$Expected)
    $actualValues = @($Actual) | ForEach-Object { "$_" -split '[,;]' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    return (@($Expected | Where-Object { $actualValues -inotcontains $_ }).Count -eq 0 -and
        @($actualValues | Where-Object { $Expected -inotcontains $_ }).Count -eq 0)
}

function ConvertTo-Node {
    param([object]$Value)
    if ($Value -is [string]) {
        $text = $Value.Trim()
        if ($text.StartsWith('{') -or $text.StartsWith('[')) {
            try { return ($text | ConvertFrom-Json -ErrorAction Stop) } catch { return $Value }
        }
    }
    return $Value
}

function Get-NamedConditionEntries {
    param([object]$Node)
    $results = [System.Collections.Generic.List[object]]::new()
    function Visit {
        param([object]$Current)
        if ($null -eq $Current) { return }
        $Current = ConvertTo-Node $Current
        if ($Current -is [string]) { return }
        if ($Current -is [System.Collections.IDictionary]) {
            $nameKey = $Current.Keys | Where-Object { "$_" -ieq 'Name' } | Select-Object -First 1
            if ($nameKey) {
                $minKey = $Current.Keys | Where-Object { "$_" -ieq 'MinCount' } | Select-Object -First 1
                $typeKey = $Current.Keys | Where-Object { "$_" -ieq 'Type' } | Select-Object -First 1
                $results.Add([pscustomobject]@{
                    Name = "$($Current[$nameKey])"
                    MinCount = if ($minKey) { "$($Current[$minKey])" } else { '' }
                    Type = if ($typeKey) { "$($Current[$typeKey])" } else { '' }
                })
            }
            foreach ($value in $Current.Values) { Visit $value }
            return
        }
        if ($Current -is [System.Collections.IEnumerable]) {
            foreach ($item in $Current) { Visit $item }
            return
        }
        $nameProperty = $Current.PSObject.Properties | Where-Object Name -ieq 'Name' | Select-Object -First 1
        if ($nameProperty) {
            $minProperty = $Current.PSObject.Properties | Where-Object Name -ieq 'MinCount' | Select-Object -First 1
            $typeProperty = $Current.PSObject.Properties | Where-Object Name -ieq 'Type' | Select-Object -First 1
            $results.Add([pscustomobject]@{
                Name = "$($nameProperty.Value)"
                MinCount = if ($minProperty) { "$($minProperty.Value)" } else { '' }
                Type = if ($typeProperty) { "$($typeProperty.Value)" } else { '' }
            })
        }
        foreach ($property in $Current.PSObject.Properties) { Visit $property.Value }
    }
    Visit $Node
    return @($results)
}

function Get-NestedValues {
    param([object]$Node, [string]$PropertyName)
    $results = [System.Collections.Generic.List[string]]::new()
    function Visit {
        param([object]$Current)
        if ($null -eq $Current) { return }
        $Current = ConvertTo-Node $Current
        if ($Current -is [string]) { return }
        if ($Current -is [System.Collections.IDictionary]) {
            foreach ($key in $Current.Keys) {
                if ("$key" -ieq $PropertyName) { $results.Add("$($Current[$key])") }
                Visit $Current[$key]
            }
            return
        }
        if ($Current -is [System.Collections.IEnumerable]) {
            foreach ($item in $Current) { Visit $item }
            return
        }
        foreach ($property in $Current.PSObject.Properties) {
            if ($property.Name -ieq $PropertyName) { $results.Add("$($property.Value)") }
            Visit $property.Value
        }
    }
    Visit $Node
    return @($results)
}

function Test-SensitivityCondition {
    param([object]$Condition)
    return (@(Get-NamedConditionEntries $Condition | Where-Object { $_.Type -ieq 'Sensitivity' }).Count -gt 0)
}

do {
    $count = $count + 1
    try {
        Set-AzContext -Subscription $sub -ErrorAction Stop | Out-Null

        $appId = $env:M365_VALIDATOR_APP_ID
        $organization = $env:M365_VALIDATOR_ORGANIZATION
        $thumbprint = $env:M365_VALIDATOR_CERT_THUMBPRINT
        if (-not $appId -or -not $organization -or -not $thumbprint) {
            throw 'The certificate-only M365_VALIDATOR_* contract requires M365_VALIDATOR_APP_ID, M365_VALIDATOR_ORGANIZATION, and M365_VALIDATOR_CERT_THUMBPRINT.'
        }
        if ($organization -notmatch '(?i)^[^.]+\.onmicrosoft\.com$') {
            throw "M365_VALIDATOR_ORGANIZATION must be the primary *.onmicrosoft.com domain; received '$organization'."
        }
        $certificate = Get-ChildItem -Path "Cert:\CurrentUser\My\$thumbprint" -ErrorAction SilentlyContinue
        if (-not $certificate -or -not $certificate.HasPrivateKey) {
            throw "M365_VALIDATOR_CERT_THUMBPRINT does not resolve to a private-key certificate in the validation account's CurrentUser\My store. TAP/password fallback is prohibited."
        }

        $exoModule = Get-Module -ListAvailable ExchangeOnlineManagement | Sort-Object Version -Descending | Select-Object -First 1
        if (-not $exoModule -or $exoModule.Version -lt [version]'3.0.0') {
            Install-Module ExchangeOnlineManagement -MinimumVersion 3.0.0 -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
        }
        Import-Module ExchangeOnlineManagement -MinimumVersion 3.0.0 -ErrorAction Stop
        $failures = [System.Collections.Generic.List[string]]::new()

        # Microsoft Learn identifies Exchange Online PowerShell as authoritative:
        # the same property returned by Security & Compliance PowerShell is always False.
        Connect-ExchangeOnline -AppId $appId -Organization $organization -CertificateThumbprint $thumbprint -ShowBanner:$false -ErrorAction Stop | Out-Null
        $auditEnabled = (Get-AdminAuditLogConfig -ErrorAction Stop).UnifiedAuditLogIngestionEnabled
        if (-not (Test-TrueValue $auditEnabled)) {
            $failures.Add("Exchange Online (Get-AdminAuditLogConfig).UnifiedAuditLogIngestionEnabled is '$auditEnabled'; expected True.")
        }
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

        Connect-IPPSSession -AppId $appId -Organization $organization -CertificateThumbprint $thumbprint -ShowBanner:$false -ErrorAction Stop | Out-Null
        $expectedNames = @('Zava Public', 'Zava Internal', 'Zava Confidential', 'Zava Highly Confidential')
        $allLabels = @(Get-Label -IncludeDetailedLabelActions -ErrorAction Stop)
        $labels = @{}
        foreach ($name in $expectedNames) {
            $matches = @($allLabels | Where-Object { $_.Name -ceq $name })
            if ($matches.Count -ne 1) { $failures.Add("Expected exactly one label named '$name'; found $($matches.Count).") }
            else {
                $labels[$name] = $matches[0]
                if (Test-TrueValue $matches[0].Disabled) { $failures.Add("Label '$name' is disabled.") }
            }
        }

        if ($labels.ContainsKey('Zava Public')) {
            $label = $labels['Zava Public']
            if (-not (Test-ExactSet $label.ContentType @('File', 'Email'))) { $failures.Add("'Zava Public' must be scoped only to File and Email.") }
            if ((Test-TrueValue $label.EncryptionEnabled) -or (Test-TrueValue $label.ApplyContentMarkingHeaderEnabled) -or (Test-TrueValue $label.ApplyContentMarkingFooterEnabled) -or (Test-TrueValue $label.ApplyWaterMarkingEnabled)) {
                $failures.Add("'Zava Public' must have no encryption, header, footer, or watermark.")
            }
        }
        if ($labels.ContainsKey('Zava Internal')) {
            $label = $labels['Zava Internal']
            if (-not (Test-ExactSet $label.ContentType @('File', 'Email'))) { $failures.Add("'Zava Internal' must be scoped only to File and Email.") }
            if (-not (Test-TrueValue $label.ApplyContentMarkingHeaderEnabled) -or "$($label.ApplyContentMarkingHeaderText)" -cne 'Zava Internal') { $failures.Add("'Zava Internal' must enable exact header text 'Zava Internal'.") }
            if ((Test-TrueValue $label.EncryptionEnabled) -or (Test-TrueValue $label.ApplyContentMarkingFooterEnabled) -or (Test-TrueValue $label.ApplyWaterMarkingEnabled)) { $failures.Add("'Zava Internal' must have no encryption, footer, or watermark.") }
        }
        foreach ($name in @('Zava Confidential', 'Zava Highly Confidential')) {
            if ($labels.ContainsKey($name)) {
                $label = $labels[$name]
                $watermark = if ($name -ceq 'Zava Confidential') { 'Confidential' } else { 'Highly Confidential' }
                $types = if ($name -ceq 'Zava Confidential') { @('File', 'Email') } else { @('File', 'Email', 'Site', 'UnifiedGroup') }
                if (-not (Test-ExactSet $label.ContentType $types)) { $failures.Add("'$name' has an incorrect scope; expected only $($types -join ', ').") }
                if (-not (Test-TrueValue $label.EncryptionEnabled)) { $failures.Add("'$name' must enable encryption.") }
                if (-not (Test-TrueValue $label.ApplyWaterMarkingEnabled) -or "$($label.ApplyWaterMarkingText)" -cne $watermark) { $failures.Add("'$name' must enable exact watermark '$watermark'.") }
                if ((Test-TrueValue $label.ApplyContentMarkingHeaderEnabled) -or (Test-TrueValue $label.ApplyContentMarkingFooterEnabled)) { $failures.Add("'$name' must not enable a header or footer.") }
                if ("$($label.EncryptionProtectionType)" -notmatch '(?i)Template|AdminDefined') { $failures.Add("'$name' must use administrator-assigned permissions.") }
                if ("$($label.EncryptionContentExpiredOnDateInDaysOrNever)" -ine 'Never' -or [int]$label.EncryptionOfflineAccessDays -ne -1) { $failures.Add("'$name' online and offline access must never expire.") }
                if ("$($label.EncryptionRightsDefinitions)" -notmatch '(?i)Co-Author|CoAuthor') { $failures.Add("'$name' must grant the internal audience Co-Author rights.") }
            }
        }
        if ($labels.ContainsKey('Zava Highly Confidential')) {
            $label = $labels['Zava Highly Confidential']
            if (-not (Test-TrueValue $label.SiteAndGroupProtectionEnabled)) { $failures.Add("'Zava Highly Confidential' must enable Groups & sites protection.") }
            if ("$($label.SiteExternalSharingControlType)" -ine 'Disabled' -or (Test-TrueValue $label.SiteAndGroupProtectionAllowAccessToGuestUsers)) { $failures.Add("'Zava Highly Confidential' must limit external sharing to people in the organization.") }
        }
        if ($labels.Count -eq 4) {
            $priorities = @($expectedNames | ForEach-Object { [int]$labels[$_].Priority })
            for ($i = 1; $i -lt $priorities.Count; $i++) {
                if ($priorities[$i] -le $priorities[$i - 1]) { $failures.Add('Label priority must increase from Zava Public through Zava Highly Confidential.'); break }
            }
        }

        $publishingMatches = @(Get-LabelPolicy -ErrorAction Stop | Where-Object { $_.Name -ceq 'Zava Global Label Policy' })
        if ($publishingMatches.Count -ne 1) { $failures.Add("Expected exactly one 'Zava Global Label Policy'; found $($publishingMatches.Count).") }
        else {
            $publishing = $publishingMatches[0]
            $published = @($publishing.Labels) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }
            foreach ($name in $expectedNames) {
                if ($labels.ContainsKey($name)) {
                    $identities = @($name, "$($labels[$name].Guid)", "$($labels[$name].ImmutableId)") | Where-Object { $_ }
                    if (@($identities | Where-Object { $published -icontains $_ }).Count -eq 0) { $failures.Add("'Zava Global Label Policy' does not publish '$name'.") }
                }
            }
            if ($published.Count -ne 4) { $failures.Add("'Zava Global Label Policy' must publish exactly four labels; found $($published.Count).") }
            if ("$($publishing.Mode)" -ine 'Enforce' -or -not (Test-AllLocation $publishing.ExchangeLocation) -or (Test-EnabledLocation $publishing.ExchangeLocationException)) { $failures.Add("'Zava Global Label Policy' must be enforced for all users without exclusions.") }
            $settings = "$($publishing.Settings) $($publishing.AdvancedSettings)"
            if ($settings -match '(?i)mandatory.{0,30}(true|1)') { $failures.Add("'Zava Global Label Policy' must not require mandatory labeling.") }
            if ($settings -match '(?i)justif.{0,40}(true|1)') { $failures.Add("'Zava Global Label Policy' must not require downgrade/removal justification.") }
        }

        $autoMatches = @(Get-AutoSensitivityLabelPolicy -ErrorAction Stop | Where-Object { $_.Name -ceq 'Zava Auto-Label Policy' })
        if ($autoMatches.Count -ne 1) { $failures.Add("Expected exactly one 'Zava Auto-Label Policy'; found $($autoMatches.Count).") }
        else {
            $auto = $autoMatches[0]
            if ("$($auto.Mode)" -cne 'TestWithoutNotifications') { $failures.Add("'Zava Auto-Label Policy' must use TestWithoutNotifications simulation mode.") }
            if ($labels.ContainsKey('Zava Highly Confidential')) {
                $targets = @('Zava Highly Confidential', "$($labels['Zava Highly Confidential'].Guid)", "$($labels['Zava Highly Confidential'].ImmutableId)") | Where-Object { $_ }
                if ($targets -inotcontains "$($auto.ApplySensitivityLabel)") { $failures.Add("'Zava Auto-Label Policy' must apply 'Zava Highly Confidential'.") }
            }
            foreach ($location in @('ExchangeLocation', 'SharePointLocation', 'OneDriveLocation')) { if (-not (Test-AllLocation $auto.$location)) { $failures.Add("'Zava Auto-Label Policy' $location must be All.") } }
            foreach ($exception in @('ExchangeLocationException', 'SharePointLocationException', 'OneDriveLocationException')) { if ($auto.PSObject.Properties[$exception] -and (Test-EnabledLocation $auto.$exception)) { $failures.Add("'Zava Auto-Label Policy' must not configure $exception.") } }
            if ($auto.PSObject.Properties['AutoEnableAfter'] -and $null -ne $auto.AutoEnableAfter -and "$($auto.AutoEnableAfter)" -notin @('', '00:00:00', '0.00:00:00')) { $failures.Add("'Zava Auto-Label Policy' must not activate automatically after simulation.") }

            $rules = @(Get-AutoSensitivityLabelRule -Policy 'Zava Auto-Label Policy' -ErrorAction Stop | Where-Object { $_.Name -ceq 'Zava High-Risk Identity Data Rule' })
            if ($rules.Count -ne 1) { $failures.Add("Expected exactly one 'Zava High-Risk Identity Data Rule'; found $($rules.Count).") }
            else {
                $rule = $rules[0]
                if (Test-TrueValue $rule.Disabled) { $failures.Add("'Zava High-Risk Identity Data Rule' is disabled.") }
                $condition = if ($rule.ContentContainsSensitiveInformation) { $rule.ContentContainsSensitiveInformation } else { $rule.AdvancedRule }
                $entries = @(Get-NamedConditionEntries $condition)
                foreach ($sit in @('Credit Card Number', 'U.S. Social Security Number')) {
                    $matches = @($entries | Where-Object { $_.Name -ieq $sit -or ($sit -eq 'U.S. Social Security Number' -and $_.Name -ieq 'U.S. Social Security Number (SSN)') })
                    if ($matches.Count -ne 1 -or $matches[0].MinCount -ne '5') { $failures.Add("Rule must contain exactly one '$sit' condition with minimum count 5.") }
                }
                if (@(Get-NestedValues $condition 'Operator') -inotcontains 'Or') { $failures.Add("'Zava High-Risk Identity Data Rule' must join the two sensitive information types with Or.") }
            }
        }

        $dlpPolicies = @(Get-DlpCompliancePolicy -ErrorAction Stop)
        foreach ($dlpRule in @(Get-DlpComplianceRule -ErrorAction Stop)) {
            $condition = if ($dlpRule.AdvancedRule) { $dlpRule.AdvancedRule } else { $dlpRule.ContentContainsSensitiveInformation }
            if (Test-SensitivityCondition $condition) {
                $reference = "$($dlpRule.Policy)"
                $parent = $dlpPolicies | Where-Object { $_.Name -ieq $reference -or "$($_.Guid)" -ieq $reference -or "$($_.ImmutableId)" -ieq $reference } | Select-Object -First 1
                if (-not $parent) { $failures.Add("Could not resolve parent policy for sensitivity-label-conditioned DLP rule '$($dlpRule.Name)'.") }
                else {
                    foreach ($required in @('ExchangeLocation', 'SharePointLocation', 'OneDriveLocation')) { if (-not (Test-EnabledLocation $parent.$required)) { $failures.Add("Sensitivity-label-conditioned DLP policy '$($parent.Name)' must enable $required.") } }
                    foreach ($forbidden in @('TeamsLocation', 'EndpointDlpLocation', 'PowerBIDlpLocation', 'OnPremisesScannerDlpLocation', 'ThirdPartyAppDlpLocation')) { if ($parent.PSObject.Properties[$forbidden] -and (Test-EnabledLocation $parent.$forbidden)) { $failures.Add("Sensitivity-label-conditioned DLP policy '$($parent.Name)' enables $forbidden; only Exchange, SharePoint, and OneDrive are permitted.") } }
                }
            }
        }

        if (-not (Get-Module -ListAvailable Microsoft.Online.SharePoint.PowerShell)) { Install-Module Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop }
        Import-Module Microsoft.Online.SharePoint.PowerShell -ErrorAction Stop
        $spoAdminUrl = $env:M365_VALIDATOR_SPO_ADMIN_URL
        if (-not $spoAdminUrl) { $spoAdminUrl = "https://$(($organization -split '\.')[0])-admin.sharepoint.com" }
        Connect-SPOService -Url $spoAdminUrl -ClientId $appId -TenantId $organization -CertificateThumbprint $thumbprint -ErrorAction Stop
        $spoTenant = Get-SPOTenant -ErrorAction Stop
        if (-not (Test-TrueValue $spoTenant.EnableAIPIntegration)) { $failures.Add("SharePoint/OneDrive EnableAIPIntegration is '$($spoTenant.EnableAIPIntegration)'; expected True.") }

        foreach ($moduleName in @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Beta.Identity.DirectoryManagement')) {
            if (-not (Get-Module -ListAvailable $moduleName)) { Install-Module $moduleName -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop }
            Import-Module $moduleName -ErrorAction Stop
        }
        Connect-MgGraph -ClientId $appId -TenantId $organization -CertificateThumbprint $thumbprint -ContextScope Process -NoWelcome -ErrorAction Stop
        # Group.Unified is the authoritative Microsoft 365 groups/sites setting.
        $groupUnified = @(Get-MgBetaDirectorySetting -All -ErrorAction Stop | Where-Object { $_.DisplayName -ceq 'Group.Unified' })
        if ($groupUnified.Count -ne 1) { $failures.Add("Expected exactly one Group.Unified directory setting; found $($groupUnified.Count).") }
        else {
            $mip = @($groupUnified[0].Values | Where-Object { $_.Name -ceq 'EnableMIPLabels' })
            if ($mip.Count -ne 1 -or -not (Test-TrueValue $mip[0].Value)) {
                $actual = if ($mip.Count -eq 1) { "$($mip[0].Value)" } else { "entry count $($mip.Count)" }
                $failures.Add("Group.Unified directory setting EnableMIPLabels is '$actual'; expected exactly one value set to True.")
            }
        }
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

        if ($failures.Count -eq 0) {
            $found = $true
            $message = @{
                Status = 'Succeeded'
                Message = "Exchange Online (Get-AdminAuditLogConfig).UnifiedAuditLogIngestionEnabled=True; SharePoint/OneDrive EnableAIPIntegration=True; Group.Unified EnableMIPLabels=True; all four exact Zava labels, 'Zava Global Label Policy', and simulated 'Zava Auto-Label Policy' with 'Zava High-Risk Identity Data Rule' satisfy the required immediate configuration. Sensitivity-label-conditioned DLP scope is compliant. Validated for $scope."
            } | ConvertTo-Json
        } else {
            $message = @{ Status = 'Failed'; Message = "Validate-Zava-Information-Protection failed for $scope: $($failures -join ' ')" } | ConvertTo-Json
        }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
        if (-not $found -and $count -lt 3) { Start-Sleep -Seconds 10 }
    }
    catch {
        $message = @{ Status = 'Failed'; Message = "Error during Validate-Zava-Information-Protection. Attempt $count of 3. Error: $($_.Exception.Message)" } | ConvertTo-Json
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
        Start-Sleep -Seconds 10
    }
} while ($count -lt 3 -and -not $found)

if (-not $found) {
    $message = @{ Status = 'Failed'; Message = "Validate-Zava-Information-Protection did not meet the required immediate tenant configuration after 3 attempts for $scope." } | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $message })
}
