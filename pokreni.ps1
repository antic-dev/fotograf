# Pokreće Fotograf na ovom računaru: http://localhost:8080
#
# Najlakše: dvoklik na pokreni.cmd
# Ili u PowerShell-u, u folderu projekta:   .\pokreni.ps1
#   -Mejl "..."      postavlja (ili menja) mejl za prijavu
#   -Lozinka "..."   postavlja (ili menja) lozinku za prijavu
#   -Brzo            preskače ponovnu izgradnju web aplikacije
#
# NAPOMENA: samo "flutter run" pokreće SAMO izgled aplikacije, bez servera,
# pa prijava i admin panel ne mogu da rade. Zato koristite ovu skriptu.

param(
  [string]$Mejl,
  [string]$Lozinka,
  [switch]$Brzo,
  [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Komanda([string]$ime) {
  if (-not (Get-Command $ime -ErrorAction SilentlyContinue)) {
    Write-Host "Nije pronađena komanda '$ime'. Instalirajte Flutter i dodajte ga u PATH: https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Red
    exit 1
  }
}

function Proveri([string]$sta) {
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Greška: $sta nije uspelo (kod $LASTEXITCODE)." -ForegroundColor Red
    exit 1
  }
}

Komanda flutter
Komanda dart

# 1. Web aplikacija
$index = Join-Path $root 'app/build/web/index.html'
if (-not $Brzo -or -not (Test-Path $index)) {
  Write-Host '==> Izgradnja web aplikacije (prvi put traje par minuta)...' -ForegroundColor Cyan
  Push-Location (Join-Path $root 'app')
  try {
    flutter pub get; Proveri 'flutter pub get'
    flutter build web --release --no-web-resources-cdn; Proveri 'flutter build web'
  } finally { Pop-Location }
}

# 2. Nalog za prijavu (čuva se na serveru; sledeći put samo Enter)
if (-not $Mejl -and -not $env:ADMIN_EMAIL) {
  Write-Host ''
  Write-Host 'Mejl i lozinka za prijavu. Prvi put su obavezni, kasnije samo pritisnite Enter.' -ForegroundColor Cyan
  $Mejl = Read-Host 'Mejl'
}
if ($Mejl) {
  if ($Mejl -notmatch '^[^@\s]+@[^@\s]+$') {
    Write-Host 'Mejl nije ispravan.' -ForegroundColor Red
    exit 1
  }
  $env:ADMIN_EMAIL = $Mejl.Trim()
}
if (-not $Lozinka -and -not $env:ADMIN_PASSWORD) {
  Write-Host 'Lozinka: najmanje 8 znakova (Enter = ostaje postojeća).'
  $sigurna = Read-Host 'Lozinka' -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sigurna)
  try { $Lozinka = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
if ($Lozinka) {
  if ($Lozinka.Length -lt 8) {
    Write-Host 'Lozinka mora imati bar 8 znakova.' -ForegroundColor Red
    exit 1
  }
  $env:ADMIN_PASSWORD = $Lozinka
}

# 3. Server (podaci se čuvaju u server\data)
$env:PORT = "$Port"
$env:HOST = '127.0.0.1'   # dostupno samo sa ovog računara
$env:PUBLIC_URL = "http://localhost:$Port"
$env:WEB_DIR = Join-Path $root 'app/build/web'

Push-Location (Join-Path $root 'server')
try {
  dart pub get; Proveri 'dart pub get'
  Write-Host ''
  Write-Host "==> Aplikacija:  http://localhost:$Port/admin" -ForegroundColor Green
  Write-Host '    Prijava:     vaš mejl i lozinka'
  Write-Host '    Zaustavljanje: Ctrl+C'
  Write-Host ''
  # Otvara pregledač čim server proradi (prvo pokretanje traje duže).
  Start-Job -ScriptBlock {
    param($url)
    for ($i = 0; $i -lt 300; $i++) {
      try {
        Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 2 | Out-Null
        Start-Process $url
        return
      } catch { Start-Sleep -Seconds 1 }
    }
  } -ArgumentList "http://localhost:$Port/admin" | Out-Null
  dart run bin/server.dart
} finally {
  Remove-Item Env:ADMIN_EMAIL, Env:ADMIN_PASSWORD -ErrorAction SilentlyContinue
  Pop-Location
}
