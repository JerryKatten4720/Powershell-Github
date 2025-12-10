# --- 1. Récupération des données (Robuste) ---
$paths = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
         "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"

Write-Host "Chargement des programmes..." -ForegroundColor Cyan

$Programmes = $paths | ForEach-Object {
    Get-ChildItem $_ -ErrorAction SilentlyContinue | ForEach-Object {
        $Key = $_
        
        # Taille
        $TailleMo = $Key.GetValue("EstimatedSize")
        if ($TailleMo) { $TailleMo = [math]::Round($TailleMo / 1024, 2) } else { $TailleMo = 0 }
        
        # Date (Conversion sécurisée pour PS 5.1)
        $InstallDateRaw = $Key.GetValue("InstallDate")
        $InstallDate = [datetime]::MinValue
        if ($InstallDateRaw -and $InstallDateRaw -match '^\d{8}$') {
            try {
                $InstallDate = [datetime]::ParseExact($InstallDateRaw, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)
            } catch {}
        }
        
        [PSCustomObject]@{
            Nom             = $Key.GetValue("DisplayName")
            Version         = $Key.GetValue("DisplayVersion")
            Chemin          = $Key.GetValue("InstallLocation")
            TailleMo        = $TailleMo
            DateInstallation = $InstallDate
        }
    }
} | Where-Object { $_.Nom }

# --- 2. Configuration du Menu ---
$IndexSelection = 0 
$ProprieteTri = "Nom" 
$OrdreTri = $true 

# Fonction utilitaire pour couper le texte trop long (pour garder les colonnes droites)
function Tronquer-Texte {
    param ($Texte, $LongueurMax)
    if ([string]::IsNullOrEmpty($Texte)) { return " ".PadRight($LongueurMax) }
    if ($Texte.Length -gt $LongueurMax) {
        return $Texte.Substring(0, $LongueurMax-3) + "..."
    }
    return $Texte.PadRight($LongueurMax)
}

function DessinerMenu {
    param(
        [Parameter(Mandatory=$true)]$ListeProgrammes,
        [Parameter(Mandatory=$true)]$Index
    )
    
    Clear-Host

    # Info Tri
    $NomTri = switch ($ProprieteTri) { "Nom" {"NOM"} "TailleMo" {"TAILLE"} "DateInstallation" {"DATE"} }
    $SensTri = if ($OrdreTri) { "A-Z (Asc)" } else { "Z-A (Desc)" }
    
    # En-tête
    Write-Host "--------------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host " TRI ACTUEL: $NomTri [$SensTri]" -ForegroundColor Yellow
    Write-Host " [N]=Tri Nom  [T]=Tri Taille  [D]=Tri Date  [P]=Ouvrir Dossier  [Q]=Quitter" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------------------------------" -ForegroundColor DarkGray
    
    # Titres des colonnes (Largeurs fixes : 50, 20, 10, 12)
    # {0,-50} signifie : aligné à gauche, prend 50 espaces
    $FormatHeader = "{0,-50} {1,-20} {2,10} {3,12}"
    $Header = $FormatHeader -f "NOM DU PROGRAMME", "VERSION", "TAILLE(Mo)", "DATE"
    Write-Host $Header -ForegroundColor Gray

    # Calcul de la plage à afficher (pour éviter de saturer la console si 500 programmes)
    # On affiche une "fenêtre" autour de la sélection si nécessaire, sinon tout.
    # Ici, on affiche tout pour rester simple, mais on formate proprement.
    
    $i = 0
    foreach ($Prog in $ListeProgrammes) {
        
        # 1. Préparation des données pour l'affichage (Troncature)
        $Aff_Nom = Tronquer-Texte -Texte $Prog.Nom -LongueurMax 50
        $Aff_Ver = Tronquer-Texte -Texte $Prog.Version -LongueurMax 20
        
        # Taille alignée à droite
        if ($Prog.TailleMo -gt 0) { $Aff_Taille = "{0,10:N2}" -f $Prog.TailleMo } 
        else { $Aff_Taille = "      -   " }

        # Date
        if ($Prog.DateInstallation -ne [datetime]::MinValue) { 
            $Aff_Date = "{0,12:yyyy-MM-dd}" -f $Prog.DateInstallation 
        } else { 
            $Aff_Date = "           -" 
        }

        # Construction de la ligne
        $Ligne = "$Aff_Nom $Aff_Ver $Aff_Taille $Aff_Date"

        # 2. Affichage avec surlignage "Natif" (Compatible PS 5.1)
        if ($i -eq $Index) {
            # Ligne sélectionnée : Fond Blanc, Texte Noir (ou Cyan sombre selon préférence)
            Write-Host $Ligne -BackgroundColor Gray -ForegroundColor Black
        } else {
            # Ligne normale
            Write-Host $Ligne
        }
        $i++
    }
}

function TrierListe {
    param($Programmes)
    if ($OrdreTri) { return $Programmes | Sort-Object $ProprieteTri }
    else { return $Programmes | Sort-Object $ProprieteTri -Descending }
}

# --- 3. Boucle Principale ---
$ProgrammesTries = TrierListe -Programmes $Programmes
$NeedsRefresh = $true

while ($true) {
    if ($NeedsRefresh) {
        DessinerMenu -ListeProgrammes $ProgrammesTries -Index $IndexSelection
        $NeedsRefresh = $false
    }

    $Cle = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

    # Navigation
    if ($Cle.VirtualKeyCode -eq 38) { # Haut
        $IndexSelection--
        if ($IndexSelection -lt 0) { $IndexSelection = $ProgrammesTries.Count - 1 }
        $NeedsRefresh = $true
    }
    elseif ($Cle.VirtualKeyCode -eq 40) { # Bas
        $IndexSelection++
        if ($IndexSelection -ge $ProgrammesTries.Count) { $IndexSelection = 0 }
        $NeedsRefresh = $true
    }
    
    # Commandes
    $Char = $Cle.Character.ToString().ToUpper()
    
    if ($Char -eq "N") {
        if ($ProprieteTri -eq "Nom") { $OrdreTri = -not $OrdreTri } 
        else { $ProprieteTri = "Nom"; $OrdreTri = $true }
        $ProgrammesTries = TrierListe -Programmes $Programmes
        $NeedsRefresh = $true
    }
    elseif ($Char -eq "T") {
        if ($ProprieteTri -eq "TailleMo") { $OrdreTri = -not $OrdreTri } 
        else { $ProprieteTri = "TailleMo"; $OrdreTri = $false }
        $ProgrammesTries = TrierListe -Programmes $Programmes
        $NeedsRefresh = $true
    }
    elseif ($Char -eq "D") {
        if ($ProprieteTri -eq "DateInstallation") { $OrdreTri = -not $OrdreTri } 
        else { $ProprieteTri = "DateInstallation"; $OrdreTri = $false }
        $ProgrammesTries = TrierListe -Programmes $Programmes
        $NeedsRefresh = $true
    }
    elseif ($Char -eq "Q") {
        Clear-Host
        break
    }
    elseif ($Char -eq "P") {
        $Prog = $ProgrammesTries[$IndexSelection]
        if ($Prog.Chemin -and (Test-Path $Prog.Chemin)) {
            Start-Process $Prog.Chemin
        } else {
            # Petit flash visuel pour indiquer l'erreur sans casser le menu
            Write-Host "`a" # Son système (Beep)
        }
    }
}