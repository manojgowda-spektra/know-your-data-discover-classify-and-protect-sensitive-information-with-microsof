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
$ssns = @('555-12-3456','447-31-8756','612-48-2291','457-55-5462','212-09-7694')
New-MinimalDocx -Path (Join-Path $Destination 'Zava-Customer-Payments.docx') -Lines @('Zava fictional customer payment test data','Credit card numbers used only for classifier testing') + $cards
New-MinimalDocx -Path (Join-Path $Destination 'Zava-Employee-Records.docx') -Lines @('Zava fictional employee identity test data','U.S. Social Security numbers used only for classifier testing') + $ssns
New-MinimalDocx -Path (Join-Path $Destination 'Zava-Mixed-Sensitive-Data.docx') -Lines @('Zava fictional mixed sensitive-data test record','Credit card numbers') + $cards + @('U.S. Social Security numbers') + $ssns
@('Zava fictional endpoint DLP test data','Credit card number: 4111 1111 1111 1111','U.S. Social Security number: 555-12-3456') | Set-Content -LiteralPath (Join-Path $Destination 'Zava-Endpoint-Sensitive-Data.txt') -Encoding UTF8
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
# Operator-only runbook

This runbook is for the lab operator, not the learner. Never place tokens, passwords, certificates, application secrets, or a Temporary Access Pass in files, scripts, command history, transcripts, or learner folders.

## 1. Before release

1. Confirm the VM is running and reachable, and run `C:\LabFiles\Helpers\Test-ZavaVmReadiness.ps1`; confirm Edge, required modules, internet connectivity and correct time synchronization.
2. Keep `C:\LabFiles\Operator` restricted to local Administrators.
3. The VM size is `Standard_D2s_v5` with `StandardSSD_LRS`. Do not change it without also updating the Azure Policy allow-list.

## 2. Confirm Microsoft 365 E5

Confirm that the tenant holds Microsoft 365 E5 and that it is assigned to the learner: sign in as the learner at `https://portal.office.com/account/#subscriptions`. If E5 is missing from the tenant, the CloudLabs licence allocation failed; resolve it before release. Allow about 30 minutes after assignment before the learner starts, because Microsoft Purview returns permission errors until the licence propagates.

## 3. Confirm administrative and Microsoft Purview role groups

Confirm Global Administrator in Microsoft Entra and the role groups `InformationProtection`, `ContentExplorerListViewer`, `ContentExplorerContentViewer`, `InsiderRiskManagement`, and `ComplianceAdministrator`, and that the assignments have propagated. Never create a `PSCredential` from a Temporary Access Pass.

## 4. Do not onboard the VM

Challenge 3 is graded on configuration only. Its first task asks the learner to confirm that **no device is onboarded**. Do not provision Defender for Endpoint onboarding, run an onboarding package, or add the VM to Microsoft Purview device onboarding.

## 5. Temporary Access Pass handoff

Issue the TAP only through Microsoft Entra authentication methods and the approved secure field. Use it only for interactive sign-in. Never treat it as a password, put it in a credential object, use it unattended, or persist it.

## 6. Final release gate

- The VM is running and the readiness script passed.
- Microsoft 365 E5 is present in the tenant, assigned to the learner, and has had time to propagate.
- Global Administrator and all five Purview role groups are assigned and propagated.
- Azure Rights Management is active (`Get-AipService` returns `Enabled`); encrypted labels cannot be created without it.
- Unified auditing is on (`(Get-AdminAuditLogConfig).UnifiedAuditLogIngestionEnabled` returns `True`). On a newly provisioned tenant `Set-AdminAuditLogConfig` can refuse with 'you first need to run Enable-OrganizationCustomization' for some time even after customization is enabled, and Challenge 2's auto-labeling policy cannot be created until auditing is on. Enable it when the instance is prepared, not at release.
- The VM is not onboarded to Microsoft Purview or Defender for Endpoint.
- The TAP was securely handed off and not persisted.
- Nothing is pre-seeded. Security Copilot is not required.

## Microsoft Learn references

- https://learn.microsoft.com/purview/purview-permissions
- https://learn.microsoft.com/purview/endpoint-dlp-learn-about
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

Use Microsoft Edge for validation. Start with the Microsoft 365 License Check shortcut. If Microsoft 365 E5 is absent, stop and contact the lab operator. This VM is deliberately not onboarded to Microsoft Purview; Challenge 3 explains why.

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
