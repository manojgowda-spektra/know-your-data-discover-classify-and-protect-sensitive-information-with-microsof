using namespace System.Net

# Note: $sub (subscription id) and $DID (deployment id) are injected by the platform.
$count = 0
$found = $false
$lastDetail = 'Validation has not run.'

$expectedTags = [ordered]@{
    ZavaIRPolicy = 'Zava Departing Employee Data Theft'
    ZavaIRTemplate = 'Data theft by departing users'
    ZavaIRPolicyType = 'Custom policy'
    ZavaIRTrigger = 'Microsoft Entra account deleted'
    ZavaIRPriorityPages = 'Both confirmed'
    ZavaIRIndicators = 'Sharing SharePoint files with people outside the organization;Sharing SharePoint folders with people outside the organization;Downloading content from SharePoint;Sending email with attachments to recipients outside the organization'
}

do {
    $count = $count + 1
    try {
        Set-AzContext -Subscription $sub -ErrorAction Stop

        # Get-AzVM without a resource-group argument returns VMs in the active subscription.
        # VM model objects expose Azure resource tags through their Tags property.
        $matchingVms = @(
            Get-AzVM -ErrorAction Stop | Where-Object {
                $null -ne $_.Tags -and
                $_.Tags.ContainsKey('DeploymentID') -and
                [string]$_.Tags['DeploymentID'] -ceq [string]$DID
            }
        )

        if ($matchingVms.Count -ne 1) {
            $lastDetail = "Expected exactly one Azure VM with preserved DeploymentID tag '$DID' in subscription '$sub', but found $($matchingVms.Count)."
        }
        else {
            $vm = $matchingVms[0]
            $missingOrInvalid = @()

            foreach ($entry in $expectedTags.GetEnumerator()) {
                if (-not $vm.Tags.ContainsKey($entry.Key)) {
                    $missingOrInvalid += "missing tag '$($entry.Key)'"
                }
                elseif ([string]$vm.Tags[$entry.Key] -cne [string]$entry.Value) {
                    $missingOrInvalid += "tag '$($entry.Key)' does not have the required exact value"
                }
            }

            $timestampKey = 'ZavaIREvidenceUtc'
            if (-not $vm.Tags.ContainsKey($timestampKey)) {
                $missingOrInvalid += "missing tag '$timestampKey'"
            }
            else {
                $timestampText = [string]$vm.Tags[$timestampKey]
                $timestamp = [DateTimeOffset]::MinValue
                $isUtcIso8601 = $timestampText -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|\+00:00)$' -and
                    [DateTimeOffset]::TryParse(
                        $timestampText,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [Globalization.DateTimeStyles]::RoundtripKind,
                        [ref]$timestamp
                    ) -and
                    $timestamp.Offset -eq [TimeSpan]::Zero

                if (-not $isUtcIso8601) {
                    $missingOrInvalid += "tag '$timestampKey' must be a valid UTC ISO 8601 timestamp recorded after the portal cross-check"
                }
            }

            if (-not $vm.Tags.ContainsKey('LabCode') -or [string]::IsNullOrWhiteSpace([string]$vm.Tags['LabCode'])) {
                $missingOrInvalid += "required deployment tag 'LabCode' was not preserved"
            }
            if (-not $vm.Tags.ContainsKey('DeploymentID') -or [string]$vm.Tags['DeploymentID'] -cne [string]$DID) {
                $missingOrInvalid += "required deployment tag 'DeploymentID' was not preserved with value '$DID'"
            }

            $secretLikeTagKeys = @(
                $vm.Tags.Keys | Where-Object {
                    [string]$_ -match '(?i)(password|passwd|secret|token|temporaryaccesspass|tap|credential)'
                }
            )
            if ($secretLikeTagKeys.Count -gt 0) {
                $missingOrInvalid += "secret-like VM tag keys are not allowed: $($secretLikeTagKeys -join ', ')"
            }

            if ($missingOrInvalid.Count -eq 0) {
                $found = $true
                $lastDetail = "VM '$($vm.Name)' in resource group '$($vm.ResourceGroupName)' preserves its LabCode and DeploymentID deployment tags and has all seven canonical Challenge 4 evidence tags with exact values, including the ordered indicators and a valid UTC ISO 8601 portal-cross-check timestamp. This validates Azure tag evidence only; tenant-side Insider Risk policy state was manually cross-checked and was not queried."
            }
            else {
                $lastDetail = "VM '$($vm.Name)' failed validation of the seven canonical Challenge 4 evidence tags and preserved LabCode/DeploymentID deployment tags: $($missingOrInvalid -join '; '). This check does not validate Microsoft 365 tenant state."
            }
        }

        if ($found) {
            $message = @{
                Status = 'Succeeded'
                Message = $lastDetail
            } | ConvertTo-Json
            Push-OutputBinding -Clobber -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body = $message
            })
        }
        else {
            $message = @{
                Status = 'Failed'
                Message = $lastDetail
            } | ConvertTo-Json
            Push-OutputBinding -Clobber -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body = $message
            })
            Start-Sleep -Seconds 10
        }
    }
    catch {
        $lastDetail = $_.Exception.Message
        $message = @{
            Status = 'Failed'
            Message = "Error during the Azure-only check of seven canonical Challenge 4 evidence tags and preserved deployment tags. Attempt $count of 3. Error: $lastDetail"
        } | ConvertTo-Json
        Push-OutputBinding -Clobber -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = $message
        })
        Start-Sleep -Seconds 10
    }
} while ($count -lt 3 -and -not $found)

if (-not $found) {
    $message = @{
        Status = 'Failed'
        Message = "The seven canonical Challenge 4 evidence tags and preserved LabCode/DeploymentID deployment tags did not pass Azure VM-tag validation for DeploymentID '$DID' in subscription '$sub' after 3 attempts. No Microsoft 365 tenant state was queried. Last detail: $lastDetail"
    } | ConvertTo-Json
    Push-OutputBinding -Clobber -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = $message
    })
}
