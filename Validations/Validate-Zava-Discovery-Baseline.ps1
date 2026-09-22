using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
# Security & Compliance PowerShell authentication uses one operator-injected,
# certificate-based app-only contract. No learner password or Temporary Access Pass
# is read or converted to a credential object.
$scope = "subscription '$sub' (deployment '$DID')"
$count = 0
$found = $false

function Test-LocationEnabled {
    param([object]$Value)

    $values = @($Value) | ForEach-Object { if ($null -ne $_) { "$($_)".Trim() } }
    return (@($values | Where-Object { $_ -and $_ -notin @('None', '{}', '[]') }).Count -gt 0)
}

function Get-NamedValues {
    param(
        [object]$Node,
        [string]$CollectionProperty
    )

    $results = [System.Collections.Generic.List[string]]::new()

    function Visit-Node {
        param([object]$Current)

        if ($null -eq $Current) { return }

        if ($Current -is [string]) {
            $text = $Current.Trim()
            if ($text.StartsWith('{') -or $text.StartsWith('[')) {
                try { Visit-Node -Current ($text | ConvertFrom-Json -ErrorAction Stop) } catch { }
            }
            return
        }

        if ($Current -is [System.Collections.IDictionary]) {
            foreach ($key in $Current.Keys) {
                $value = $Current[$key]
                if (("$key") -ieq $CollectionProperty) {
                    foreach ($entry in @($value)) {
                        if ($entry -is [System.Collections.IDictionary] -and $entry.Contains('name')) {
                            $results.Add("$($entry['name'])")
                        } elseif ($entry.PSObject.Properties['name']) {
                            $results.Add("$($entry.name)")
                        }
                    }
                }
                Visit-Node -Current $value
            }
            return
        }

        if ($Current -is [System.Collections.IEnumerable]) {
            foreach ($item in $Current) { Visit-Node -Current $item }
            return
        }

        foreach ($property in $Current.PSObject.Properties) {
            if ($property.Name -ieq $CollectionProperty) {
                foreach ($entry in @($property.Value)) {
                    if ($entry.PSObject.Properties['name']) {
                        $results.Add("$($entry.name)")
                    }
                }
            }
            Visit-Node -Current $property.Value
        }
    }

    Visit-Node -Current $Node
    return @($results)
}

function Get-PropertyValues {
    param(
        [object]$Node,
        [string]$PropertyName
    )

    $results = [System.Collections.Generic.List[string]]::new()

    function Visit-PropertyNode {
        param([object]$Current)

        if ($null -eq $Current -or $Current -is [string]) { return }

        if ($Current -is [System.Collections.IDictionary]) {
            foreach ($key in $Current.Keys) {
                if (("$key") -ieq $PropertyName) {
                    $results.Add("$($Current[$key])")
                }
                Visit-PropertyNode -Current $Current[$key]
            }
            return
        }

        if ($Current -is [System.Collections.IEnumerable]) {
            foreach ($item in $Current) { Visit-PropertyNode -Current $item }
            return
        }

        foreach ($property in $Current.PSObject.Properties) {
            if ($property.Name -ieq $PropertyName) {
                $results.Add("$($property.Value)")
            }
            Visit-PropertyNode -Current $property.Value
        }
    }

    Visit-PropertyNode -Current $Node
    return @($results)
}

do {
    $count = $count + 1
    try {
        Set-AzContext -Subscription $sub -ErrorAction Stop | Out-Null

        if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
            Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
        }
        Import-Module ExchangeOnlineManagement -ErrorAction Stop

        $appId = $env:M365_VALIDATOR_APP_ID
        $organization = $env:M365_VALIDATOR_ORGANIZATION
        $certificateThumbprint = $env:M365_VALIDATOR_CERT_THUMBPRINT

        if (-not $appId -or -not $organization -or -not $certificateThumbprint) {
            throw 'The operator-injected settings M365_VALIDATOR_APP_ID, M365_VALIDATOR_ORGANIZATION, and M365_VALIDATOR_CERT_THUMBPRINT are required.'
        }
        try {
            [void][guid]::Parse($appId)
        } catch {
            throw 'M365_VALIDATOR_APP_ID must contain a valid GUID value.'
        }

        $certificatePath = "Cert:\CurrentUser\My\$certificateThumbprint"
        $certificate = Get-Item -LiteralPath $certificatePath -ErrorAction Stop
        if (-not $certificate.HasPrivateKey) {
            throw "The certificate at '$certificatePath' does not have a private key."
        }

        Connect-IPPSSession -AppId $appId -Organization $organization -CertificateThumbprint $certificateThumbprint -ShowBanner:$false -ErrorAction Stop | Out-Null

        $failures = [System.Collections.Generic.List[string]]::new()
        $policyName = 'Zava Discovery Baseline'
        $ruleName = 'Zava Discovery Sensitive Data Rule'

        $matchingPolicies = @(Get-DlpCompliancePolicy -ErrorAction Stop | Where-Object { $_.Name -ceq $policyName })
        if ($matchingPolicies.Count -ne 1) {
            $failures.Add("Expected exactly one policy named '$policyName'; found $($matchingPolicies.Count).")
        } else {
            $policy = $matchingPolicies[0]

            if ("$($policy.Mode)" -cne 'TestWithoutNotifications') {
                $failures.Add("Policy mode is '$($policy.Mode)'; expected 'TestWithoutNotifications' (simulation mode).")
            }

            if (-not (Test-LocationEnabled -Value $policy.SharePointLocation)) {
                $failures.Add('SharePointLocation is not enabled.')
            }
            if (-not (Test-LocationEnabled -Value $policy.OneDriveLocation)) {
                $failures.Add('OneDriveLocation is not enabled.')
            }

            $forbiddenLocations = @(
                'ExchangeLocation',
                'TeamsLocation',
                'EndpointDlpLocation',
                'PowerBIDlpLocation',
                'OnPremisesScannerDlpLocation',
                'ThirdPartyAppDlpLocation'
            )
            foreach ($locationProperty in $forbiddenLocations) {
                if ($policy.PSObject.Properties[$locationProperty] -and
                    (Test-LocationEnabled -Value $policy.$locationProperty)) {
                    $failures.Add("$locationProperty must be disabled; the policy may include only SharePoint and OneDrive.")
                }
            }

            $matchingRules = @(Get-DlpComplianceRule -Policy $policyName -ErrorAction Stop | Where-Object { $_.Name -ceq $ruleName })
            if ($matchingRules.Count -ne 1) {
                $failures.Add("Expected exactly one rule named '$ruleName' in '$policyName'; found $($matchingRules.Count).")
            } else {
                $rule = $matchingRules[0]
                $condition = $rule.ContentContainsSensitiveInformation
                if ($null -eq $condition -and $rule.PSObject.Properties['AdvancedRule']) {
                    $condition = $rule.AdvancedRule
                }

                $sitNames = @(Get-NamedValues -Node $condition -CollectionProperty 'sensitivetypes' | Sort-Object -Unique)
                $expectedSitNames = @('Credit Card Number', 'U.S. Social Security Number')
                $missingSits = @($expectedSitNames | Where-Object { $sitNames -cnotcontains $_ })
                $unexpectedSits = @($sitNames | Where-Object { $expectedSitNames -cnotcontains $_ })
                $operators = @(Get-PropertyValues -Node $condition -PropertyName 'Operator')
                $labelNames = @(Get-NamedValues -Node $condition -CollectionProperty 'labels')

                if ($missingSits.Count -gt 0) {
                    $failures.Add("The content condition is missing sensitive information type(s): $($missingSits -join ', ').")
                }
                if ($unexpectedSits.Count -gt 0) {
                    $failures.Add("The content condition includes unexpected sensitive information type(s): $($unexpectedSits -join ', ').")
                }
                if ($operators -inotcontains 'Or') {
                    $failures.Add("The two sensitive information types are not joined by an 'Or' operator.")
                }
                if ($labelNames.Count -gt 0) {
                    $failures.Add('The content condition includes sensitivity labels; it must contain only the two required sensitive information types.')
                }
            }
        }

        if ($failures.Count -eq 0) {
            $found = $true
            $message = @{
                Status  = 'Succeeded'
                Message = "Policy '$policyName' and rule '$ruleName' are configured in TestWithoutNotifications simulation mode, scoped only to SharePoint and OneDrive, with Credit Card Number OR U.S. Social Security Number. Validated for organization '$organization' and $scope."
            } | ConvertTo-Json
        } else {
            $message = @{
                Status  = 'Failed'
                Message = "Validation failed for organization '$organization' and $scope: $($failures -join ' ')"
            } | ConvertTo-Json
        }

        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $message
        })

        if (-not $found -and $count -lt 3) {
            Start-Sleep -Seconds 10
        }
    }
    catch {
        $message = @{
            Status  = 'Failed'
            Message = "Error during Security & Compliance check. Attempt $count of 3. Error: $($_.Exception.Message)"
        } | ConvertTo-Json
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $message
        })
        if ($count -lt 3) {
            Start-Sleep -Seconds 10
        }
    }
} while ($count -lt 3 -and -not $found)

# Post-loop: if every attempt failed, emit a final failure JSON so CloudLabs
# always sees a structured result.
if (-not $found) {
    $message = @{
        Status  = 'Failed'
        Message = "Policy 'Zava Discovery Baseline' and rule 'Zava Discovery Sensitive Data Rule' did not meet the required immediate configuration state after 3 attempts for $scope."
    } | ConvertTo-Json
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $message
    })
}
