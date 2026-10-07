# exRegMon

PowerShell-script som overvåker en registernøkkel i sanntid og skriver ut hva som endres. Standard er Visma Business-nøkkelen `HKLM\SOFTWARE\WOW6432Node\Visma\Visma Business\CurrentVersion`.

## Slik fungerer det

1. Ved oppstart tas et snapshot av alle verdier under nøkkelen, inkludert undernøkler.
2. Scriptet registrerer en CIM-hendelse (`RegistryTreeChangeEvent`) som utløses når noe under nøkkelen endres.
3. Ved hver hendelse tas et nytt snapshot som sammenlignes med det forrige. Forskjellene skrives ut:
   - `[+] LAGT TIL`: ny verdi
   - `[*] ENDRET`: verdi med gammel og ny verdi
   - `[-] SLETTET`: verdi som er fjernet

## Bruk

```powershell
.\exRegMon.ps1
```

Trykk Ctrl+C for å stoppe. Hendelsesregistreringen ryddes da bort.

## Konfigurasjon

Endre variablene øverst i `exRegMon.ps1`:

| Variabel | Beskrivelse |
|---|---|
| `$registryHive` | Registergren, f.eks. `HKEY_LOCAL_MACHINE` eller `HKEY_USERS`. `HKEY_CURRENT_USER` støttes ikke av hendelsen (se under) |
| `$registryKeyPath` | Nøkkelen som skal overvåkes, uten hive |

## Krav

- Windows PowerShell 5.1 eller PowerShell 7 (testet at hendelsesregistreringen fungerer i 7.6)
- Tilgang til å lese nøkkelen. Noen nøkler krever at PowerShell kjøres som administrator.

## Begrensninger

`RegistryTreeChangeEvent` støtter ikke `HKEY_CURRENT_USER` og gir feilen «Invalid query». For å overvåke en nøkkel i din egen bruker, bruk `HKEY_USERS` og legg bruker-SID først i nøkkelstien, f.eks. `$registryKeyPath = "<SID>\Software\..."`. SID-en får du med `[Security.Principal.WindowsIdentity]::GetCurrent().User.Value`.

Obs: scriptet leser selv verdiene via PowerShell-stasjonen (`HKLM:` osv. etter mapping), og `HKEY_USERS` mappes til `HKU:`, som må være tilgjengelig. Dette er ikke testet.
