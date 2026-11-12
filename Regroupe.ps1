<#
.SYNOPSIS
    Regroupe les parties créées par Decouper-Zip.ps1 en un seul fichier.

.EXEMPLE
    .\Regrouper-Zip.ps1 -Fichier "C:\data\archive.zip"

    Cherche archive.zip.001, .002, ... et reconstitue archive.zip.
    Si archive.zip.sha256 est présent, l'intégrité est vérifiée.

.EXEMPLE
    .\Regrouper-Zip.ps1 -Fichier "C:\data\archive.zip" -Sortie "D:\restaure.zip"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Fichier,      # nom du fichier d'origine (sans .001)

    [string]$Sortie        # facultatif : chemin du fichier reconstitué
)

$ErrorActionPreference = 'Stop'

# Accepte aussi qu'on donne directement "archive.zip.001"
$base = $Fichier -replace '\.\d{3}$', ''
$dossier = Split-Path -Parent $base
if ([string]::IsNullOrEmpty($dossier)) { $dossier = (Get-Location).ProviderPath }
$dossier = (Resolve-Path -LiteralPath $dossier).ProviderPath
$nom  = Split-Path -Leaf $base
$base = Join-Path $dossier $nom

if (-not $Sortie) { $Sortie = $base }
$Sortie = [System.IO.Path]::GetFullPath($Sortie)

$parties = Get-ChildItem -LiteralPath $dossier -File |
    Where-Object { $_.Name -match ('^' + [regex]::Escape($nom) + '\.\d{3}$') } |
    Sort-Object Name

if (-not $parties) { throw "Aucune partie trouvée pour '$nom' dans $dossier" }

# Vérifie qu'il ne manque aucune partie (001, 002, 003...)
for ($k = 0; $k -lt $parties.Count; $k++) {
    $attendu = '{0}.{1:D3}' -f $nom, ($k + 1)
    if ($parties[$k].Name -ne $attendu) { throw "Partie manquante : $attendu" }
}

if (Test-Path -LiteralPath $Sortie) {
    throw "Le fichier '$Sortie' existe déjà. Supprimez-le ou utilisez -Sortie."
}

$out = [System.IO.File]::Create($Sortie)
try {
    foreach ($p in $parties) {
        $in = [System.IO.File]::OpenRead($p.FullName)
        try { $in.CopyTo($out, 4MB) } finally { $in.Close() }
        Write-Host "Ajoutée : $($p.Name)"
    }
}
finally { $out.Close() }

# Contrôle d'intégrité
$fichierHash = "$base.sha256"
if (Test-Path -LiteralPath $fichierHash) {
    Write-Host "Vérification de l'intégrité..."
    $attendu = (Get-Content -LiteralPath $fichierHash -TotalCount 1).Trim()
    $obtenu  = (Get-FileHash -LiteralPath $Sortie -Algorithm SHA256).Hash
    if ($attendu -eq $obtenu) {
        Write-Host "OK : fichier identique à l'original -> $Sortie" -ForegroundColor Green
    } else {
        Write-Host "ERREUR : l'empreinte ne correspond pas, le fichier est corrompu." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Fichier reconstitué -> $Sortie (pas de .sha256, intégrité non vérifiée)" -ForegroundColor Yellow
}