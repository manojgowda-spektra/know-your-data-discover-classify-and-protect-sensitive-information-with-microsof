Param(
    [Parameter(Mandatory = $false)] [string] $AzureUserName,
    [Parameter(Mandatory = $false)] [string] $AzurePassword,
    [Parameter(Mandatory = $false)] [string] $AzureTenantID,
    [Parameter(Mandatory = $false)] [string] $AzureSubscriptionID,
    [Parameter(Mandatory = $false)] [string] $ODLID,
    [Parameter(Mandatory = $false)] [string] $InstallCloudLabsShadow = 'true',
    [Parameter(Mandatory = $false)] [string] $DeploymentID,
    [Parameter(Mandatory = $false)] [string] $vmAdminUsername,
    [Parameter(Mandatory = $false)] [string] $vmAdminPassword,
    [Parameter(Mandatory = $false)] [string] $trainerUserName,
    [Parameter(Mandatory = $false)] [string] $trainerUserPassword
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$transcriptPath = 'C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt'
New-Item -ItemType Directory -Path (Split-Path -Path $transcriptPath -Parent) -Force | Out-Null
Start-Transcript -Path $transcriptPath -Append -Force

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $commonBaseUri = 'https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/'
    $labRoot = 'C:\LabFiles'
    $publicDesktop = 'C:\Users\Public\Desktop'
    $bootstrapRoot = 'C:\ProgramData\CloudLabs'
    $operatorRoot = Join-Path $labRoot 'Operator'
    $evidenceRoot = Join-Path $labRoot 'Evidence'
    $helperRoot = Join-Path $labRoot 'Helpers'
    @($labRoot, $publicDesktop, $bootstrapRoot, $operatorRoot, $evidenceRoot, $helperRoot) | ForEach-Object { New-Item -ItemType Directory -Path $_ -Force | Out-Null }

    function Invoke-DownloadWithRetry {
        param([Parameter(Mandatory = $true)] [uri] $Uri, [Parameter(Mandatory = $true)] [string] $OutFile, [int] $Attempts = 3)
        $parent = Split-Path -Path $OutFile -Parent
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
            try {
                Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
                if ((Get-Item -LiteralPath $OutFile).Length -le 0) { throw "Downloaded file is empty: $OutFile" }
                return
            } catch {
                if ($attempt -eq $Attempts) { throw }
                Start-Sleep -Seconds (5 * $attempt)
            }
        }
    }

    function CreateCredFile {
        $credentialWork = Join-Path $bootstrapRoot 'CommonAssets'
        New-Item -ItemType Directory -Path $credentialWork -Force | Out-Null
        foreach ($assetName in @('AzureCreds.txt', 'AzureCreds.ps1')) {
            $downloadPath = Join-Path $credentialWork ($assetName + '.download')
            Invoke-DownloadWithRetry -Uri ([uri]($commonBaseUri + $assetName)) -OutFile $downloadPath
            Remove-Item -LiteralPath $downloadPath -Force
        }
        $metadata = [ordered]@{ AzureUserName = $AzureUserName; AzureTenantID = $AzureTenantID; AzureSubscriptionID = $AzureSubscriptionID; ODLID = $ODLID; DeploymentID = $DeploymentID }
        $textPath = Join-Path $credentialWork 'AzureCreds.txt'
        @('CloudLabs Azure metadata (no password is stored in this file)', "AzureUserName=$($metadata.AzureUserName)", "AzureTenantID=$($metadata.AzureTenantID)", "AzureSubscriptionID=$($metadata.AzureSubscriptionID)", "ODLID=$($metadata.ODLID)", "DeploymentID=$($metadata.DeploymentID)") | Set-Content -LiteralPath $textPath -Encoding UTF8 -Force
        $scriptPath = Join-Path $credentialWork 'AzureCreds.ps1'
        @('# CloudLabs Azure metadata only. No password or noninteractive credential is stored.', ('$AzureUserName = ' + "'" + ([string]$metadata.AzureUserName).Replace("'", "''") + "'"), ('$AzureTenantID = ' + "'" + ([string]$metadata.AzureTenantID).Replace("'", "''") + "'"), ('$AzureSubscriptionID = ' + "'" + ([string]$metadata.AzureSubscriptionID).Replace("'", "''") + "'"), ('$ODLID = ' + "'" + ([string]$metadata.ODLID).Replace("'", "''") + "'"), ('$DeploymentID = ' + "'" + ([string]$metadata.DeploymentID).Replace("'", "''") + "'")) | Set-Content -LiteralPath $scriptPath -Encoding UTF8 -Force
        foreach ($assetName in @('AzureCreds.txt', 'AzureCreds.ps1')) {
            $safePath = Join-Path $credentialWork $assetName
            Copy-Item -LiteralPath $safePath -Destination (Join-Path $labRoot $assetName) -Force
            Copy-Item -LiteralPath $safePath -Destination (Join-Path $publicDesktop $assetName) -Force
        }
    }

    function ConvertTo-Boolean { param([string] $Value); if ([string]::IsNullOrWhiteSpace($Value)) { return $true }; return $Value.Trim() -notmatch '^(false|0|no|off)$' }
    function Ensure-ShadowAccount {
        if (-not (ConvertTo-Boolean -Value $InstallCloudLabsShadow)) { Write-Output 'CloudLabs VM Shadow account creation was explicitly disabled.'; return }
        if ([string]::IsNullOrWhiteSpace($trainerUserName) -or [string]::IsNullOrWhiteSpace($trainerUserPassword)) { throw 'VM Shadow is enabled, but trainerUserName or trainerUserPassword is empty.' }
        $securePassword = ConvertTo-SecureString $trainerUserPassword -AsPlainText -Force
        $existing = Get-LocalUser -Name $trainerUserName -ErrorAction SilentlyContinue
        if ($null -eq $existing) { New-LocalUser -Name $trainerUserName -Password $securePassword -PasswordNeverExpires -UserMayNotChangePassword -Description 'CloudLabs VM Shadow instructor account' | Out-Null } else { $existing | Set-LocalUser -Password $securePassword -PasswordNeverExpires $true }
        foreach ($group in @('Remote Desktop Users', 'Administrators')) {
            $isMember = Get-LocalGroupMember -Group $group -ErrorAction Stop | Where-Object { $_.Name -eq "$env:COMPUTERNAME\$trainerUserName" }
            if (-not $isMember) { Add-LocalGroupMember -Group $group -Member $trainerUserName }
        }
        $securePassword = $null
    }

    function Install-RequiredModule {
        param([Parameter(Mandatory = $true)] [string] $Name)
        if (Get-Module -ListAvailable -Name $Name) { Write-Output "PowerShell module is already available: $Name"; return }
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try { Install-Module -Name $Name -Scope AllUsers -Repository PSGallery -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop; return } catch { if ($attempt -eq 3) { throw }; Start-Sleep -Seconds (10 * $attempt) }
        }
    }
    function Ensure-Edge {
        $edgePath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
        if (Test-Path -LiteralPath $edgePath) { return }
        $edgeMsi = Join-Path $bootstrapRoot 'MicrosoftEdgeEnterpriseX64.msi'
        Invoke-DownloadWithRetry -Uri 'https://go.microsoft.com/fwlink/?linkid=2109047&Channel=Stable&language=en&brand=M100' -OutFile $edgeMsi
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $edgeMsi, '/qn', '/norestart') -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010)) { throw "Microsoft Edge installation failed with exit code $($process.ExitCode)." }
        Remove-Item -LiteralPath $edgeMsi -Force -ErrorAction SilentlyContinue
    }
    function New-WebShortcut { param([Parameter(Mandatory = $true)] [string] $Name, [Parameter(Mandatory = $true)] [string] $Url); @('[InternetShortcut]', "URL=$Url", 'IconIndex=0') | Set-Content -LiteralPath (Join-Path $publicDesktop ($Name + '.url')) -Encoding ASCII -Force }

    CreateCredFile
    Ensure-ShadowAccount
    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null }
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    @('ExchangeOnlineManagement','Microsoft.Graph.Authentication','Microsoft.Graph.Users','Microsoft.Graph.Users.Actions','Microsoft.Graph.Identity.DirectoryManagement','Microsoft.Graph.Identity.Governance','Microsoft.Online.SharePoint.PowerShell') | ForEach-Object { Install-RequiredModule -Name $_ }
    Ensure-Edge
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget -and -not (Get-Command pwsh.exe -ErrorAction SilentlyContinue)) {
        try { & $winget.Source install --id Microsoft.PowerShell --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null } catch { Write-Warning 'PowerShell 7 installation was not available in the SYSTEM context. Windows PowerShell 5.1 remains configured for the lab.' }
    }
    @('Challenge-01','Challenge-02','Challenge-03','Challenge-04','Screenshots','Validation') | ForEach-Object { New-Item -ItemType Directory -Path (Join-Path $evidenceRoot $_) -Force | Out-Null }

    $syntheticHelper = @'
[CmdletBinding()]
param([string]$Destination = 'C:\LabFiles\Evidence\Challenge-01')
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
function ConvertTo-XmlText([string]$Value) { return [System.Security.SecurityElement]::Escape($Value) }
function New-MinimalDocx {
    param([string]$Path, [string[]]$Lines)
    if (Test-Path -LiteralPath $Path) { throw "Refusing to overwrite existing learner evidence: $Path" }
    $work = Join-Path $env:TEMP ([guid]::NewGuid().Guid)
    New-Item -ItemType Directory -Path (Join-Path $work '_rels') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $work 'word') -Force | Out-Null
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>' | Set-Content -LiteralPath (Join-Path $work '[Content_Types].xml') -Encoding UTF8
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>' | Set-Content -LiteralPath (Join-Path $work '_rels\.rels') -Encoding UTF8
    $paragraphs = ($Lines | ForEach-Object { '<w:p><w:r><w:t xml:space="preserve">' + (ConvertTo-XmlText $_) + '</w:t></w:r></w:p>' }) -join ''
    $document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>' + $paragraphs + '<w:sectPr/></w:body></w:document>'
    Set-Content -LiteralPath (Join-Path $work 'word\document.xml') -Value $document -Encoding UTF8
    [System.IO.Compression.ZipFile]::CreateFromDirectory($work, $Path)
    Remove-Item -LiteralPath $work -Recurse -Force
}
$cards = @('4111 1111 1111 1111','5555 5555 5555 4444','4012 8888 8888 1881','4222 2222 2222 2','3782 822463 10005')
$ssns = @('219-09-9999','078-05-1120','457-55-5462','212-09-7694','001-01-0001')
New-MinimalDocx -Path (Join-Path $Destination 'Zava-Customer-Payments.docx') -Lines @('Zava fictional customer payment test data','Credit card numbers used only for classifier testing') + $cards
New-MinimalDocx -Path (Join-Path $Destination 'Zava-Employee-Records.docx') -Lines @('Zava fictional employee identity test data','U.S. Social Security numbers used only for classifier testing') + $ssns
New-MinimalDocx -Path (Join-Path $Destination 'Zava-Mixed-Sensitive-Data.docx') -Lines @('Zava fictional mixed sensitive-data test record','Credit card numbers') + $cards + @('U.S. Social Security numbers') + $ssns
@('Zava fictional endpoint DLP test data','Credit card number: 4111 1111 1111 1111','U.S. Social Security number: 219-09-9999') | Set-Content -LiteralPath (Join-Path $Destination 'Zava-Endpoint-Sensitive-Data.txt') -Encoding UTF8
Write-Host "Created four synthetic files in $Destination"
'@
    Set-Content -LiteralPath (Join-Path $helperRoot 'New-ZavaSyntheticEvidence.ps1') -Value $syntheticHelper -Encoding UTF8 -Force

    $readinessScript = @'
$results = [ordered]@{ ComputerName = $env:COMPUTERNAME; CheckedAtUtc = (Get-Date).ToUniversalTime().ToString('o'); WindowsVersion = [Environment]::OSVersion.VersionString; EdgeInstalled = Test-Path 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'; SenseService = (Get-Service -Name Sense -ErrorAction SilentlyContinue).Status.ToString(); RequiredModules = @{} }
foreach ($module in @('ExchangeOnlineManagement','Microsoft.Graph.Authentication','Microsoft.Online.SharePoint.PowerShell')) { $results.RequiredModules[$module] = [bool](Get-Module -ListAvailable -Name $module) }
$results | ConvertTo-Json -Depth 4
'@
    Set-Content -LiteralPath (Join-Path $helperRoot 'Test-ZavaVmReadiness.ps1') -Value $readinessScript -Encoding UTF8 -Force

    $operatorRunbook = @'
# Operator-only hot-instance runbook

This runbook is for the lab operator, not the learner. The Azure resources may remain provisioned for at least 24 hours before delivery; the VM does not need to run continuously. Never place onboarding packages, tokens, passwords, certificates, application secrets, or a Temporary Access Pass in files, scripts, command history, transcripts, or learner folders.

## 1. Hot-instance operating checklist

1. Keep the Azure resources provisioned for the required 24-hour preparation period.
2. Start the VM only for onboarding, policy synchronization, telemetry collection, and release checks.
3. Deallocate the VM after every such window.
4. Start the VM shortly before learner release and complete the final connectivity, health, policy-sync, and telemetry checks.
5. Retain `Standard_B2s` with `StandardSSD_LRS`. Run a representative-workload pilot; if the pilot shows sustained memory pressure or unacceptable responsiveness, use the approved `Standard_B2ms` fallback while retaining `StandardSSD_LRS`.
6. Run `C:\LabFiles\Helpers\Test-ZavaVmReadiness.ps1`; confirm Edge, required modules, current Windows updates, internet connectivity, correct time synchronization, and removable-media test capability.
7. Keep `C:\LabFiles\Operator` restricted to local Administrators.

## 2. Assign Microsoft 365 E5

Connect interactively with an operator administrator identity. Assign the learner the available `SPE_E5` SKU, set usage location, and verify Microsoft 365 E5 at `https://portal.office.com/account/#subscriptions`.

## 3. Assign administrative and Microsoft Purview role groups

Assign Global Administrator in Microsoft Entra and the following Security & Compliance PowerShell role-group identities: `InformationProtection`, `ContentExplorerListViewer`, `ContentExplorerContentViewer`, `InsiderRiskManagement`, and `ComplianceAdministrator`. Confirm all assignments have propagated. Never create a `PSCredential` from a Temporary Access Pass.

## 4. Provision Defender for Endpoint and onboard the VM

1. Start the VM for the onboarding window, provision Microsoft Defender for Endpoint, and wait for tenant initialization.
2. Enable Microsoft Purview device onboarding and obtain a fresh Windows 10/11 local-script onboarding package from the current tenant portal.
3. Stage it temporarily in an Administrator-only location, run it elevated, then securely remove all onboarding material.
4. Confirm the `Sense` service and verify that the device is recently seen and healthy in both Microsoft Defender and Microsoft Purview.
5. Confirm current connectivity, healthy configuration, policy sync, and readiness to receive Endpoint DLP updates.
6. Deallocate after the window. Start shortly before release and repeat all release checks.

The operator remediates any failed health state. The learner never onboards or repairs the device.

## 5. Temporary Access Pass handoff

Issue the TAP only through Microsoft Entra authentication methods and the approved secure field. Use it only for interactive bootstrap sign-in. Never treat it as a password, put it in a credential object, use it unattended, or persist it.

## 6. Final release gate

- Resources have remained provisioned for at least 24 hours; the VM ran only in required windows and was deallocated after each window.
- The representative-workload pilot passed on `Standard_B2s`, or the approved `Standard_B2ms` fallback was selected; the disk remains `StandardSSD_LRS`.
- The VM was started shortly before release and all connectivity, onboarding, telemetry, health, and policy-sync checks passed.
- Microsoft 365 E5, Global Administrator, and all five Purview role groups are assigned and propagated.
- Defender provisioning is complete; the device is healthy and ready for Endpoint DLP updates.
- Edge and removable-media testing work; the TAP was securely handed off and not persisted.
- Nothing is pre-seeded. Security Copilot is not required.

## Microsoft Learn references

- https://learn.microsoft.com/purview/purview-permissions
- https://learn.microsoft.com/purview/device-onboarding-overview
- https://learn.microsoft.com/purview/device-onboarding-health-reports-dashboard
- https://learn.microsoft.com/defender-endpoint/configure-endpoints-gp#verify-device-onboarding
- https://learn.microsoft.com/entra/identity/authentication/howto-authentication-temporary-access-pass
- https://learn.microsoft.com/powershell/azure/protect-secrets
- https://learn.microsoft.com/azure/virtual-machines/extensions/custom-script-windows#extension-schema
'@
    $operatorRunbookPath = Join-Path $operatorRoot 'Operator-Hot-Instance-Runbook.md'
    Set-Content -LiteralPath $operatorRunbookPath -Value $operatorRunbook -Encoding UTF8 -Force
    & icacls.exe $operatorRoot /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' | Out-Null

    New-WebShortcut -Name 'Microsoft Purview' -Url 'https://purview.microsoft.com'
    New-WebShortcut -Name 'Microsoft 365 License Check' -Url 'https://portal.office.com/account/#subscriptions'
    New-WebShortcut -Name 'Microsoft Entra' -Url 'https://entra.microsoft.com'
    New-WebShortcut -Name 'Microsoft Defender' -Url 'https://security.microsoft.com'
    $learnerReadme = @'
# Zava lab VM

Use Microsoft Edge for validation. Start with the Microsoft 365 License Check shortcut. If Microsoft 365 E5 is absent, or if the device is not healthy in Microsoft Purview, stop and contact the lab operator.

Nothing is pre-seeded in the tenant. Security Copilot is not provisioned and is not required. You generate your own evidence.

Folders:
- `C:\LabFiles\Evidence` — save challenge evidence here.
- `C:\LabFiles\Helpers\New-ZavaSyntheticEvidence.ps1` — run only when directed to create fictional test documents.

Never put live personal, payment, authentication, or tenant-secret data in lab evidence.
'@
    Set-Content -LiteralPath (Join-Path $labRoot 'README.md') -Value $learnerReadme -Encoding UTF8 -Force
    Copy-Item -LiteralPath (Join-Path $labRoot 'README.md') -Destination (Join-Path $publicDesktop 'Zava-Lab-README.md') -Force
    $state = [ordered]@{ Stage = 1; StageName = 'Hot-instance Windows endpoint'; ComputerName = $env:COMPUTERNAME; DeploymentID = $DeploymentID; CompletedAtUtc = (Get-Date).ToUniversalTime().ToString('o'); CommonMetadataAssetsCreated = $true; SecretsPersistedInLearnerAssets = $false; ShadowRequested = ConvertTo-Boolean -Value $InstallCloudLabsShadow; OperatorRunbook = $operatorRunbookPath; TenantProvisioningPerformedByCse = $false; Note = 'Microsoft 365 licensing, roles, Defender provisioning, and onboarding are operator-only interactive prerequisites.' }
    $state | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $bootstrapRoot 'Stage-01-State.json') -Encoding UTF8 -Force
    Write-Output 'Stage 1 CloudLabs bootstrap completed successfully. Microsoft 365 tenant provisioning remains an operator-only hot-instance task.'
} catch {
    Write-Error "Stage 1 bootstrap failed: $($_.Exception.Message)"
    throw
} finally {
    Stop-Transcript
}
