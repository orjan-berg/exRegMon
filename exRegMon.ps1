# Tweak disse variablene etter ønske
$registryHive = "HKEY_LOCAL_MACHINE"
$registryKeyPath = "SOFTWARE\WOW6432Node\Visma\Visma Business\CurrentVersion"

# Mapp HKEY-navn til PowerShell PS-Drive
$hiveMap = @{
    "HKEY_LOCAL_MACHINE" = "HKLM"
    "HKEY_CURRENT_USER"  = "HKCU"
    "HKEY_CLASSES_ROOT"  = "HKCR"
    "HKEY_USERS"         = "HKU"
}

$drive = if ($hiveMap.ContainsKey($registryHive)) { $hiveMap[$registryHive] } else { $registryHive }
$registryPath = "$drive" + ':' + "\$registryKeyPath"

# Opprett trådsikker hashtabell for deling av tilstand
$global:regState = [hashtable]::Synchronized(@{})

# Hjelpefunksjon for oppstartssnapshot
function Get-InitialRegistrySnapshot {
    param([string]$path)
    $snapshot = @{}
    if (Test-Path $path) {
        $items = @(Get-Item -Path $path -ErrorAction SilentlyContinue) + @(Get-ChildItem -Path $path -Recurse -ErrorAction SilentlyContinue)
        foreach ($item in $items) {
            try {
                foreach ($valName in $item.GetValueNames()) {
                    $uniqueKey = "$($item.Name)|$valName"
                    $snapshot[$uniqueKey] = $item.GetValue($valName)
                }
            } catch {}
        }
    }
    return $snapshot
}

Write-Host "Bygger start-snapshot av registry..." -ForegroundColor Cyan
$initialData = Get-InitialRegistrySnapshot -path $registryPath
foreach ($k in $initialData.Keys) { $global:regState[$k] = $initialData[$k] }
Write-Host "Start-snapshot fullført ($($global:regState.Count) verdier registrert)." -ForegroundColor Green

Write-Host "`nRegistry-overvåking startet (PowerShell 5.1)..." -ForegroundColor Green
Write-Host "Overvåker tre: $registryPath" -ForegroundColor Green
Write-Host "Trykk Ctrl+C for å stoppe overvåking.`n" -ForegroundColor Yellow

$action = {
    try {
        # La operativsystemet fullføre skriving til disk/registry
        Start-Sleep -Milliseconds 200

        $targetRegistryPath = $Event.MessageData
        Write-Host ">>> Registry-endring oppdaget $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Yellow

        # Ta nytt snapshot direkte i hendelsesblokken
        $newSnapshot = @{}
        if (Test-Path $targetRegistryPath) {
            $items = @(Get-Item -Path $targetRegistryPath -ErrorAction SilentlyContinue) + @(Get-ChildItem -Path $targetRegistryPath -Recurse -ErrorAction SilentlyContinue)
            foreach ($item in $items) {
                try {
                    foreach ($valName in $item.GetValueNames()) {
                        $uniqueKey = "$($item.Name)|$valName"
                        $newSnapshot[$uniqueKey] = $item.GetValue($valName)
                    }
                } catch {}
            }
        }

        # 1. Sammenlign for nye og endrede verdier
        foreach ($key in $newSnapshot.Keys) {
            $parts = $key -split '\|'
            $regKey = $parts[0]
            $valName = if ($parts[1] -eq "") { "(Standard)" } else { $parts[1] }
            $newVal = $newSnapshot[$key]

            if (-not $global:regState.ContainsKey($key)) {
                Write-Host "  [+] LAGT TIL:" -ForegroundColor Green
                Write-Host "      Nøkkel: $regKey" -ForegroundColor Cyan
                Write-Host "      Verdi:  $valName = $newVal" -ForegroundColor Green
            }
            elseif ($global:regState[$key] -ne $newVal) {
                Write-Host "  [*] ENDRET:" -ForegroundColor Yellow
                Write-Host "      Nøkkel: $regKey" -ForegroundColor Cyan
                Write-Host "      Verdi:  $valName" -ForegroundColor Yellow
                Write-Host "      Gammel: $($global:regState[$key])" -ForegroundColor Red
                Write-Host "      Ny:     $newVal" -ForegroundColor Green
            }
        }

        # 2. Sammenlign for slettede verdier
        $existingKeys = @($global:regState.Keys)
        foreach ($key in $existingKeys) {
            if (-not $newSnapshot.ContainsKey($key)) {
                $parts = $key -split '\|'
                $regKey = $parts[0]
                $valName = if ($parts[1] -eq "") { "(Standard)" } else { $parts[1] }
                Write-Host "  [-] SLETTET:" -ForegroundColor Red
                Write-Host "      Nøkkel: $regKey" -ForegroundColor Cyan
                Write-Host "      Verdi:  $valName (var: $($global:regState[$key]))" -ForegroundColor Red
            }
        }

        # Oppdater minnetilstanden
        $global:regState.Clear()
        foreach ($k in $newSnapshot.Keys) {
            $global:regState[$k] = $newSnapshot[$k]
        }
    }
    catch {
        Write-Host "  [!] Feil under behandling av endring: $_" -ForegroundColor Red
    }
}

# Formater sti for WQL-spørringen
$queryKeyPath = $registryKeyPath.Replace("\", "\\")
$query = "SELECT * FROM RegistryTreeChangeEvent WHERE Hive='$registryHive' AND RootPath='$queryKeyPath'"

# Fjern evt. eksisterende hendelser
Unregister-Event -SourceIdentifier "RunKeyChange" -ErrorAction SilentlyContinue
Get-Job -Name "RunKeyChange" -ErrorAction SilentlyContinue | Remove-Job -Force

# Registrer CIM-hendelse
Register-CimIndicationEvent -Namespace "root/default" -Query $query -SourceIdentifier "RunKeyChange" -MessageData $registryPath -Action $action

Write-Host "CIM-hendelse registrert! Venter på endringer..." -ForegroundColor Green

try {
    while ($true) {
        Start-Sleep -Seconds 1
    }
}
finally {
    Unregister-Event -SourceIdentifier "RunKeyChange" -ErrorAction SilentlyContinue
    Get-Job -Name "RunKeyChange" -ErrorAction SilentlyContinue | Remove-Job -Force
    Write-Host "`nOvervåking stoppet og hendelse avregistrert." -ForegroundColor Yellow
}