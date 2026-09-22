using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
# Microsoft Purview configuration is tenant control-plane state, not an ARM resource.
# Security & Compliance PowerShell authentication uses the same operator-provided
# certificate contract as the other Microsoft 365 validators. No learner password
# or Temporary Access Pass is read or converted to a credential object.
$scope = "subscription '$sub' (deployment '$DID')"
$count = 0
$found = $false

function ConvertTo-SearchText {
    param([Parameter(ValueFromPipeline = $true)]$InputObject)

    if ($null -eq $InputObject) {
        return ""
    }

    try {
        return (($InputObject | ConvertTo-Json -Depth 100 -Compress -ErrorAction Stop) -replace '\u0026', '&').ToLowerInvariant()
    }
    catch {
        return ([string]$InputObject).ToLowerInvariant()
    }
}

function Test-LocationSelected {
    param($Value)

    if ($null -eq $Value) {
        return $false
    }

    $text = ConvertTo-SearchText $Value
    return -not [string]::IsNullOrWhiteSpace($text) -and $text -notin @('null', '[]', '{}', '""')
}

function Test-DevicesOnlyPolicy {
    param($Policy)

    if (-not (Test-LocationSelected $Policy.EndpointDlpLocation)) {
        return $false
    }

    # These are the non-device DLP workload properties currently exposed on
    # Get-DlpCompliancePolicy objects. A selected value in any one fails the check.
    $nonDeviceLocations = @(
        'ExchangeLocation',
        'SharePointLocation',
        'OneDriveLocation',
        'TeamsLocation',
        'PowerBILocation',
        'OnPremisesScannerDlpLocation',
        'ThirdPartyAppDlpLocation',
        'ThirdPartyAppDlpLocationException'
    )

    foreach ($propertyName in $nonDeviceLocations) {
        $property = $Policy.PSObject.Properties[$propertyName]
        if ($null -ne $property -and (Test-LocationSelected $property.Value)) {
            return $false
        }
    }

    return $true
}

function Test-EnforcingPolicy {
    param($Policy)

    $mode = ([string]$Policy.Mode).ToLowerInvariant()
    return $mode -in @('enable', 'enabled', 'enforce')
}

function Test-SensitiveInformationCondition {
    param(
        $Rule,
        [string]$CreditCardId,
        [string]$SsnId
    )

    $condition = $Rule.ContentContainsSensitiveInformation
    if ($null -eq $condition) {
        # Advanced rules can expose the condition only through AdvancedRule.
        $condition = $Rule.AdvancedRule
    }

    $text = ConvertTo-SearchText $condition
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $false
    }

    $hasCreditCard = $text.Contains('credit card number') -or $text.Contains($CreditCardId.ToLowerInvariant())
    $hasSsn = $text.Contains('u.s. social security number') -or
              $text.Contains('us social security number') -or
              $text.Contains($SsnId.ToLowerInvariant())
    $hasEitherOperator = $text -match '"operator"\s*:\s*"or"' -or
                         $text -match '\boperator\s*[=:]\s*or\b'

    return $hasCreditCard -and $hasSsn -and $hasEitherOperator
}

function Test-BlockedEndpointAction {
    param(
        $Rule,
        [string[]]$ActionPatterns,
        [string]$RequiredGroup
    )

    $restrictions = @($Rule.EndpointDlpRestrictions)
    if ($restrictions.Count -eq 0 -or $null -eq $restrictions[0]) {
        return $false
    }

    foreach ($restriction in $restrictions) {
        $text = ConvertTo-SearchText $restriction
        $hasAction = $false
        foreach ($pattern in $ActionPatterns) {
            if ($text -match $pattern) {
                $hasAction = $true
                break
            }
        }

        $isBlock = $text -match '"(?:value|action|restriction|settingvalue)"\s*:\s*"block"' -or
                   $text -match '\b(?:value|action|restriction|settingvalue)\s*[=:]\s*block\b'
        $hasGroup = [string]::IsNullOrWhiteSpace($RequiredGroup) -or
                    $text.Contains($RequiredGroup.ToLowerInvariant())

        if ($hasAction -and $isBlock -and $hasGroup) {
            return $true
        }
    }

    return $false
}

do {
    $count = $count + 1
    try {
        Set-AzContext -Subscription $sub -ErrorAction Stop | Out-Null

        if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
            Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
        }
        Import-Module ExchangeOnlineManagement -ErrorAction Stop

        $appId = $env:M365_VALIDATOR_APP_ID
        $organization = $env:M365_VALIDATOR_ORGANIZATION
        $certificateThumbprint = $env:M365_VALIDATOR_CERT_THUMBPRINT

        if ([string]::IsNullOrWhiteSpace($appId) -or
            [string]::IsNullOrWhiteSpace($organization) -or
            [string]::IsNullOrWhiteSpace($certificateThumbprint)) {
            throw 'The platform app-only settings M365_VALIDATOR_APP_ID, M365_VALIDATOR_ORGANIZATION, and M365_VALIDATOR_CERT_THUMBPRINT are required.'
        }

        $certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$certificateThumbprint" -ErrorAction Stop
        if (-not $certificate.HasPrivateKey) {
            throw "Certificate '$certificateThumbprint' in CurrentUser\My does not have an accessible private key."
        }

        Connect-IPPSSession -AppId $appId -Organization $organization -CertificateThumbprint $certificateThumbprint -ShowBanner:$false -ErrorAction Stop | Out-Null

        $creditCard = Get-DlpSensitiveInformationType -Identity 'Credit Card Number' -ErrorAction Stop
        $ssn = Get-DlpSensitiveInformationType -Identity 'U.S. Social Security Number' -ErrorAction Stop
        $creditCardId = [string]$creditCard.Identity
        if ([string]::IsNullOrWhiteSpace($creditCardId)) { $creditCardId = [string]$creditCard.Id }
        $ssnId = [string]$ssn.Identity
        if ([string]::IsNullOrWhiteSpace($ssnId)) { $ssnId = [string]$ssn.Id }

        $expected = @(
            @{
                Policy = 'Zava Block Removable Storage'
                Rule = 'Zava Block Sensitive Data to Removable Storage Rule'
                Actions = @('copy.*(?:removable|usb)', '(?:removable|usb).*copy')
                Group = ''
            },
            @{
                Policy = 'Zava Block Unsanctioned Cloud Uploads'
                Rule = 'Zava Block Sensitive Uploads to Unsanctioned Cloud Rule'
                Actions = @('upload.*(?:cloud|service.*domain)', '(?:cloud|service.*domain).*upload')
                Group = 'Zava Unsanctioned Cloud Storage'
            },
            @{
                Policy = 'Zava Block Generative AI Sharing'
                Rule = 'Zava Block Sensitive Data to Generative AI Rule'
                Actions = @('upload.*(?:cloud|service.*domain)', '(?:cloud|service.*domain).*upload')
                SecondActions = @('paste.*(?:browser|supported)', '(?:browser|supported).*paste')
                Group = 'Generative AI Websites'
            }
        )

        $allPolicies = @(Get-DlpCompliancePolicy -IncludeExtendedProperties $true -ErrorAction Stop)
        $failures = [System.Collections.Generic.List[string]]::new()

        foreach ($item in $expected) {
            $policyMatches = @($allPolicies | Where-Object { $_.Name -ceq $item.Policy })
            if ($policyMatches.Count -ne 1) {
                $failures.Add("Expected exactly one policy named '$($item.Policy)'; found $($policyMatches.Count).")
                continue
            }

            $policy = $policyMatches[0]
            if (-not (Test-DevicesOnlyPolicy $policy)) {
                $failures.Add("Policy '$($item.Policy)' is not scoped only to Devices.")
            }
            if (-not (Test-EnforcingPolicy $policy)) {
                $failures.Add("Policy '$($item.Policy)' is not in enforcing mode; current Mode is '$($policy.Mode)'.")
            }

            $policyRules = @(Get-DlpComplianceRule -Policy $item.Policy -ErrorAction Stop)
            $ruleMatches = @($policyRules | Where-Object { $_.Name -ceq $item.Rule })
            if ($ruleMatches.Count -ne 1) {
                $failures.Add("Expected exactly one rule named '$($item.Rule)' in '$($item.Policy)'; found $($ruleMatches.Count).")
                continue
            }
            if ($policyRules.Count -ne 1) {
                $failures.Add("Policy '$($item.Policy)' must contain only its canonical rule; found $($policyRules.Count) rules.")
            }

            $rule = $ruleMatches[0]
            if (-not (Test-SensitiveInformationCondition -Rule $rule -CreditCardId $creditCardId -SsnId $ssnId)) {
                $failures.Add("Rule '$($item.Rule)' does not expose an either/OR content condition containing both 'Credit Card Number' and 'U.S. Social Security Number'.")
            }
            if (-not (Test-BlockedEndpointAction -Rule $rule -ActionPatterns $item.Actions -RequiredGroup $item.Group)) {
                $groupDetail = if ([string]::IsNullOrWhiteSpace($item.Group)) { '' } else { " for group '$($item.Group)'" }
                $failures.Add("Rule '$($item.Rule)' does not expose the required Block action$groupDetail.")
            }
            if ($item.ContainsKey('SecondActions') -and
                -not (Test-BlockedEndpointAction -Rule $rule -ActionPatterns $item.SecondActions -RequiredGroup $item.Group)) {
                $failures.Add("Rule '$($item.Rule)' does not expose a Block action for Paste to supported browsers using built-in group 'Generative AI Websites'.")
            }
        }

        if ($failures.Count -eq 0) {
            $found = $true
            $message = @{
                Status  = 'Succeeded'
                Message = "Validated the exact three Zava Endpoint DLP policies and rules: enforcing mode, Devices-only scope, either-SIT conditions, required Block actions, rule reference to 'Zava Unsanctioned Cloud Storage', and built-in 'Generative AI Websites'. Microsoft exposes no supported public PowerShell cmdlet or API to enumerate Sensitive service domain group members, so the exact custom members dropbox.com, drive.google.com, and box.com require the documented portal cross-check and were not falsely graded. Policy sync, policy tips, and Activity explorer telemetry were not checked. Validated for $scope."
            } | ConvertTo-Json
        }
        else {
            $message = @{
                Status  = 'Failed'
                Message = ("Validation failed for ${scope}: " + ($failures -join ' ') + " Custom group membership for dropbox.com, drive.google.com, and box.com is not queryable through a supported public PowerShell cmdlet/API and must be portal-cross-checked; policy sync, policy tips, and Activity explorer are intentionally not graded.")
            } | ConvertTo-Json
        }

        Push-OutputBinding -Clobber -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $message
        })

        if (-not $found) {
            Start-Sleep -Seconds 10
        }
    }
    catch {
        $message = @{
            Status  = 'Failed'
            Message = "Error during Zava Endpoint DLP configuration check for $scope. Attempt $count of 3. Error: $($_.Exception.Message)"
        } | ConvertTo-Json
        Push-OutputBinding -Clobber -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $message
        })
        Start-Sleep -Seconds 10
    }
} while ($count -lt 3 -and -not $found)

# Post-loop: if every attempt failed, emit a final failure JSON so CloudLabs
# always sees a structured result.
if (-not $found) {
    $message = @{
        Status  = 'Failed'
        Message = "Validate-Zava-Endpoint-DLP did not find a fully compliant immediate tenant configuration after 3 attempts for $scope. Sensitive service domain group membership remains a required portal cross-check because Microsoft exposes no supported public enumeration cmdlet/API."
    } | ConvertTo-Json
    Push-OutputBinding -Clobber -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $message
    })
}
