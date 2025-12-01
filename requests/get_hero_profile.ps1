<#
get_hero_profile.ps1
PowerShell adaptation du script get_hero_profile.sh pour Windows.

Usage:
  .\get_hero_profile.ps1           -> interactive : demande l'Invite/NameCode
  .\get_hero_profile.ps1 --login   -> interactive : demande username puis password (masqué)
  .\get_hero_profile.ps1 --help
Note: ne commite jamais ce script avec des identifiants en clair.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$OUTDIR = "gotest_outputs"
if (-not (Test-Path -Path $OUTDIR)) {
  New-Item -ItemType Directory -Path $OUTDIR | Out-Null
}

$URL = "https://pcmob.parse.gemsofwar.com/call_function"
$CLIENT_VER = "8.9.0"

function Do-Request {
  param(
    [string]$Payload,
    [string]$OutFile,
    [string]$HdrFile
  )

  $headers = @{
    Accept = "application/json"
    "User-Agent" = "Mozilla/5.0 (Windows) PowerShell"
    Origin = "https://pcmob.parse.gemsofwar.com"
  }

  try {
    $resp = Invoke-WebRequest -Uri $URL -Method Post -Body $Payload -ContentType 'application/json' -Headers $headers -UseBasicParsing -ErrorAction Stop
  } catch {
    # If Invoke-WebRequest fails with a web error, try to capture response
    if ($_.Exception.Response -ne $null) {
      $webResp = $_.Exception.Response
      try {
        $stream = $webResp.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $content = $reader.ReadToEnd()
        $reader.Close()
      } catch {
        $content = ""
      }
      # Write status line manually if available
      $statusCode = [int]$webResp.StatusCode
      $statusDesc = $webResp.StatusDescription
      "HTTP/1.1 $statusCode $statusDesc" | Out-File -Encoding utf8 -FilePath $HdrFile
      foreach ($k in $webResp.Headers.AllKeys) {
        "$k: $($webResp.Headers[$k])" | Out-File -Encoding utf8 -Append -FilePath $HdrFile
      }
      $content | Out-File -Encoding utf8 -FilePath $OutFile
      return $statusCode.ToString()
    } else {
      throw
    }
  }

  # Save body
  $resp.Content | Out-File -Encoding utf8 -FilePath $OutFile

  # Save headers with a status line
  $statusLine = "HTTP/1.1 $($resp.StatusCode) $($resp.StatusDescription)"
  $statusLine | Out-File -Encoding utf8 -FilePath $HdrFile
  foreach ($k in $resp.Headers.Keys) {
    "$k: $($resp.Headers[$k])" | Out-File -Encoding utf8 -Append -FilePath $HdrFile
  }

  return $resp.StatusCode.ToString()
}

function Pretty-Print {
  param([string]$File)
  if (-not (Test-Path -Path $File)) {
    Write-Host "(Fichier introuvable: $File)"
    return
  }

  # Try PowerShell JSON formatting first
  try {
    Get-Content -Raw -Path $File | ConvertFrom-Json | ConvertTo-Json -Depth 10
  } catch {
    # fallback: if jq exists use it, else print raw
    if (Get-Command jq -ErrorAction SilentlyContinue) {
      & jq . $File
    } else {
      Write-Host "(Installer jq pour un affichage coloré/formaté: choco install jq ou scoop install jq)"
      Get-Content -Path $File -Raw
    }
  }
}

function Fetch-By-NameCode {
  param([string]$NameCode)
  $nc = ($NameCode -replace "`r|`n", "") -replace '^\s+|\s+$',''
  if ([string]::IsNullOrWhiteSpace($nc)) {
    Write-Host "NameCode vide. Abandon."
    return 1
  }

  $safe = ($nc -replace '[^A-Za-z0-9_.-]','_')
  $out = Join-Path $OUTDIR ("get_hero_profile_{0}.json" -f $safe)
  $hdr = Join-Path $OUTDIR ("get_hero_profile_{0}.http" -f $safe)

  $payload = @{ functionName = "get_hero_profile"; clientVersion = $CLIENT_VER; NameCode = $nc } | ConvertTo-Json -Compress
  Write-Host "Récupération du profil pour NameCode=$nc ..."
  $http = Do-Request -Payload $payload -OutFile $out -HdrFile $hdr
  Write-Host "HTTP: $http"
  Write-Host "Body: $out"
  Write-Host "Headers: $hdr"
  Write-Host ""
  Pretty-Print -File $out
  return 0
}

function Do-Login-And-Fetch {
  param(
    [string]$User,
    [string]$Pass
  )

  $user = ($User -replace "`r|`n","")
  if ([string]::IsNullOrWhiteSpace($user)) {
    Write-Host "Username vide. Abandon."
    return 1
  }

  $safe = ($user -replace '[^A-Za-z0-9_.-]','_')
  $login_out = Join-Path $OUTDIR ("login_user_{0}.json" -f $safe)
  $login_hdr = Join-Path $OUTDIR ("login_user_{0}.http" -f $safe)

  $payload = @{ functionName = "login_user"; username = $user; password = $Pass; clientVersion = $CLIENT_VER } | ConvertTo-Json -Compress
  Write-Host "Tentative de connexion pour username=$user ..."
  $http = Do-Request -Payload $payload -OutFile $login_out -HdrFile $login_hdr
  Write-Host "HTTP: $http"
  Write-Host "Login body: $login_out"
  Write-Host "Login headers: $login_hdr"
  Write-Host ""
  Pretty-Print -File $login_out
  Write-Host ""

  # Try to extract NameCode using PowerShell JSON parsing
  try {
    $j = Get-Content -Raw -Path $login_out | ConvertFrom-Json -ErrorAction Stop
    $namecode = $null
    if ($null -ne $j.result) {
      foreach ($prop in @('NameCode','nameCode','InviteCode','inviteCode','username')) {
        if ($j.result.PSObject.Properties.Name -contains $prop) {
          $val = $j.result.$prop
          if ($val) { $namecode = $val; break }
        }
      }
      if (-not $namecode -and $j.result.user -ne $null) {
        if ($j.result.user.PSObject.Properties.Name -contains 'NameCode') {
          $namecode = $j.result.user.NameCode
        }
      }
    }
    if ($namecode) {
      Write-Host "NameCode détecté dans la réponse de login: $namecode"
      Write-Host ""
      Fetch-By-NameCode -NameCode $namecode | Out-Null
      return 0
    } else {
      Write-Host "Aucun NameCode détecté automatiquement dans la réponse de login."
      Write-Host "Ouvre $login_out pour inspecter la réponse (ou utilise --invite)."
      return 1
    }
  } catch {
    Write-Host "Impossible de parser la réponse JSON automatiquement. Ouvrez $login_out pour inspecter manuellement."
    return 1
  }
}

function Print-Usage {
  $script = Split-Path -Leaf $PSCommandPath
  Write-Host "Usage:"
  Write-Host "  .\$script               -> demande l'Invite/NameCode"
  Write-Host "  .\$script --login       -> demande username puis password (prompt interactif)"
  Write-Host "  .\$script --help"
}

# ---------- Main ----------
param(
  [Parameter(Position=0,Mandatory=$false)]
  [string]$Arg1
)

if ($Arg1 -eq "--help" -or $Arg1 -eq "-h") {
  Print-Usage
  exit 0
}

if ($Arg1 -eq "--login") {
  $USERNAME = Read-Host -Prompt "Username"
  if ([string]::IsNullOrWhiteSpace($USERNAME)) {
    Write-Host "Username vide. Abandon."
    exit 1
  }
  $securePass = Read-Host -Prompt "Password" -AsSecureString
  $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
  try {
    $PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
  } finally {
    if ($BSTR -ne [IntPtr]::Zero) {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }
  }
  if ([string]::IsNullOrWhiteSpace($PASSWORD)) {
    Write-Host "Password vide. Abandon."
    exit 1
  }
  Do-Login-And-Fetch -User $USERNAME -Pass $PASSWORD | Out-Null
  exit $LASTEXITCODE
}

# Par défaut : demander Invite/NameCode
$INV = Read-Host -Prompt "Enter Invite/NameCode"
if ([string]::IsNullOrWhiteSpace($INV)) {
  Write-Host "Aucun code fourni. Abandon."
  exit 1
}
Fetch-By-NameCode -NameCode $INV
