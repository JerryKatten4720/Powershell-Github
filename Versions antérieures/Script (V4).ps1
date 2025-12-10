# Définition des chemins du Registre où les programmes sont listés
$paths = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
         "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"

# --- 1. Récupération des données des programmes (LOGIQUE DE DATE AMÉLIORÉE) ---
$Programmes = $paths | ForEach-Object {
    Get-ChildItem $_ -ErrorAction SilentlyContinue | ForEach-Object {
        $Key = $_
        
        # Tentative de récupération de la taille estimée (en Mo)
        $TailleMo = $Key.GetValue("EstimatedSize")
        if ($TailleMo) {
            $TailleMo = [math]::Round($TailleMo / 1024, 2)
        } else {
            $TailleMo = 0
        }
        
        # Récupération de la date d'installation
        $InstallDateRaw = $Key.GetValue("InstallDate")
        $InstallDate = [datetime]::MinValue
        
        # Tenter la conversion si la valeur est une chaîne de 8 chiffres
        if ($InstallDateRaw -and $InstallDateRaw -match '^\d{8}$') {
            # Utilisation de ParseExact pour forcer le format YYYYMMDD
            # On utilise une boucle Try/Catch pour être sûr que même ParseExact ne crashe pas la boucle si la date est invalide (comme 20251035)
            try {
                $InstallDate = [datetime]::ParseExact($InstallDateRaw, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture)
            }
            catch {
                # Si la conversion échoue (date invalide), elle reste [datetime]::MinValue
            }
        }
        
        # Création de l'objet personnalisé avec toutes les infos nécessaires
        [PSCustomObject]@{
            Nom             = $Key.GetValue("DisplayName")
            Version         = $Key.GetValue("DisplayVersion")
            Chemin          = $Key.GetValue("InstallLocation")
            TailleMo        = $TailleMo
            DateInstallation = $InstallDate
        }
    }
} | Where-Object { $_.Nom }

# --- 2. Configuration du Menu Interactif ---
$IndexSelection = 0 
$ProprieteTri = "Nom" 
$OrdreTri = $true 

$HighlightOn = "`e[7m"
$HighlightOff = "`e[0m"

# Fonction pour dessiner le menu
function DessinerMenu {
    param(
        [Parameter(Mandatory=$true)]$ListeProgrammes,
        [Parameter(Mandatory=$true)]$Index
    )
    
    Clear-Host

    # Affichage des informations de tri
    $TriInfo = switch ($ProprieteTri) {
        "Nom" { "Nom (`e[1mN`e[0m)" }
        "TailleMo" { "Taille (`e[1mT`e[0m)" }
        "DateInstallation" { "Date (`e[1mD`e[0m)" }
    }
    $OrdreInfo = if ($OrdreTri) { "Ascendant" } else { "Descendant" }
    
    Write-Host "--- Liste des Programmes Installés ---"
    Write-Host "Tri actuel: $TriInfo - $OrdreInfo"
    Write-Host "Utilisez les flèches pour naviguer. `e[1mP`e[0m = Ouvrir le Chemin. `e[1mQ`e[0m = Quitter."
    Write-Host "--------------------------------------"
    
    # Affichage de l'en-tête (manuellement pour l'alignement)
    $HeaderNom = "Nom du Programme".PadRight(50)
    $HeaderVersion = "Version".PadRight(15)
    $HeaderTaille = "Taille (Mo)".PadRight(10)
    $HeaderDate = "Date d'Install.".PadRight(15)
    Write-Host "$HeaderNom $HeaderVersion $HeaderTaille $HeaderDate"

    # Affichage de la liste des programmes
    for ($i = 0; $i -lt $ListeProgrammes.Count; $i++) {
        $LigneProgramme = $ListeProgrammes[$i]
        
        # --- CORRECTION DE L'ERREUR D'EXPRESSION NULL ET DE CONVERSION DE DATE ---
        
        # 1. Vérification et Formatage du Nom
        $Nom = if ($LigneProgramme.Nom) { 
            ($LigneProgramme.Nom).PadRight(50) 
        } else {
            "N/A".PadRight(50)
        }
        
        # 2. Vérification et Formatage de la Version (CORRIGÉ : ne doit pas être $null pour PadRight)
        $Version = if ($LigneProgramme.Version) { 
            ($LigneProgramme.Version).PadRight(15) 
        } else {
            "N/A".PadRight(15)
        }
        
        # 3. Formatage de la Taille
        $Taille = ($LigneProgramme.TailleMo -as [string]).PadRight(10)
        
        # 4. Formatage de la Date (CORRIGÉ : on vérifie la valeur MinValue, pas de cast ici)
        if ($LigneProgramme.DateInstallation -ne [datetime]::MinValue) { 
            # Comme la conversion a eu lieu à la source, on peut appeler ToString() en toute confiance.
            $Date = $LigneProgramme.DateInstallation.ToString("yyyy-MM-dd") 
        } else { 
            $Date = "N/A" 
        }
        $Date = $Date.PadRight(15)

        $LigneAfficher = "$Nom $Version $Taille $Date"

        if ($i -eq $Index) {
            # Afficher la ligne sélectionnée avec l'inversion ANSI
            Write-Host "$HighlightOn$LigneAfficher$HighlightOff"
        } else {
            # Afficher les autres lignes normalement
            Write-Host $LigneAfficher
        }
    }
}

# Fonction pour trier la liste
function TrierListe {
    param(
        [Parameter(Mandatory=$true)]$Programmes
    )

    if ($OrdreTri) {
        return $Programmes | Sort-Object $ProprieteTri
    } else {
        return $Programmes | Sort-Object $ProprieteTri -Descending
    }
}

# Tri initial
$ProgrammesTries = TrierListe -Programmes $Programmes

# --- 3. Boucle principale du Menu ---
DessinerMenu -ListeProgrammes $ProgrammesTries -Index $IndexSelection

while ($true) {
    $Cle = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

    # Gestion des touches de navigation (Haut, Bas)
    if ($Cle.VirtualKeyCode -eq 38) { # Haut (Up Arrow)
        $IndexSelection--
    } elseif ($Cle.VirtualKeyCode -eq 40) { # Bas (Down Arrow)
        $IndexSelection++
    }
    
    # S'assurer que l'index reste dans les limites de la liste
    if ($IndexSelection -lt 0) {
        $IndexSelection = $ProgrammesTries.Count - 1
    } elseif ($IndexSelection -ge $ProgrammesTries.Count) {
        $IndexSelection = 0
    }

    # Gestion des touches de tri (N, T, D)
    $CleChar = $Cle.Character.ToString().ToUpper()
    $RedrawNeeded = $false
    
    switch ($CleChar) {
        "N" { # Nom
            if ($ProprieteTri -eq "Nom") { $OrdreTri = -not $OrdreTri }
            else { $ProprieteTri = "Nom"; $OrdreTri = $true }
            $ProgrammesTries = TrierListe -Programmes $Programmes
            $RedrawNeeded = $true
        }
        "T" { # Taille
            if ($ProprieteTri -eq "TailleMo") { $OrdreTri = -not $OrdreTri }
            else { $ProprieteTri = "TailleMo"; $OrdreTri = $false } 
            $ProgrammesTries = TrierListe -Programmes $Programmes
            $RedrawNeeded = $true
        }
        "D" { # Date d'installation
            if ($ProprieteTri -eq "DateInstallation") { $OrdreTri = -not $OrdreTri }
            else { $ProprieteTri = "DateInstallation"; $OrdreTri = $false } 
            $ProgrammesTries = TrierListe -Programmes $Programmes
            $RedrawNeeded = $true
        }
        "P" { # Ouvrir le chemin d'accès
            $ProgrammeSelectionne = $ProgrammesTries[$IndexSelection]
            $Chemin = $ProgrammeSelectionne.Chemin

            Clear-Host
            Write-Host "--- Ouverture du Chemin ---"
            Write-Host "Programme : $($ProgrammeSelectionne.Nom)"
            
            if ($Chemin -and (Test-Path -Path $Chemin -PathType Container)) {
                Write-Host "Chemin : $Chemin" -ForegroundColor Green
                Start-Process -FilePath $Chemin
                Write-Host "`nAppuyez sur une touche pour retourner au menu..."
                $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                $RedrawNeeded = $true
            } else {
                Write-Host "Chemin non trouvé ou non spécifié pour ce programme." -ForegroundColor Red
                if ($Chemin) { Write-Host "(Chemin enregistré : $Chemin)" }
                Write-Host "`nAppuyez sur une touche pour retourner au menu..."
                $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                $RedrawNeeded = $true
            }
        }
        "Q" { # Quitter
            Clear-Host
            return
        }
    }

    # Redessiner le menu si un mouvement de flèche ou un tri a eu lieu
    if ($Cle.VirtualKeyCode -in 38, 40 -or $RedrawNeeded) {
        DessinerMenu -ListeProgrammes $ProgrammesTries -Index $IndexSelection
    }
}