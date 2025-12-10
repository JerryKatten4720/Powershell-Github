# Définition des chemins du Registre où les programmes sont listés
$paths = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
         "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"

# --- 1. Récupération des données des programmes ---
$Programmes = $paths | ForEach-Object {
    # On utilise -ErrorAction SilentlyContinue car certains chemins peuvent être inaccessibles
    Get-ChildItem $_ -ErrorAction SilentlyContinue | ForEach-Object {
        $Key = $_
        
        # Tentative de récupération de la taille estimée (en Mo)
        $TailleMo = $Key.GetValue("EstimatedSize")
        if ($TailleMo) {
            # EstimatedSize est généralement en KB, on convertit en Mo
            $TailleMo = [math]::Round($TailleMo / 1024, 2)
        } else {
            $TailleMo = 0
        }
        
        # Récupération de la date d'installation
        $InstallDate = $Key.GetValue("InstallDate")
        if ($InstallDate -and $InstallDate -match '^\d{8}$') {
            # Le format est souvent YYYYMMDD
            $InstallDate = [datetime]::ParseExact($InstallDate, 'yyyyMMdd', $null)
        } else {
            $InstallDate = [datetime]::MinValue
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
$IndexSelection = 0 # L'index du programme actuellement sélectionné
$ProprieteTri = "Nom" # Propriété de tri par défaut
$OrdreTri = $true # $true = Ascendant (A-Z, Petit->Grand, Ancien->Récent), $false = Descendant

# Constantes ANSI pour le surlignage (REVERTED ANSI)
# \e[7m active l'inversion des couleurs (Reverted/Reverse)
# \e[0m réinitialise les attributs
$HighlightOn = "`e[7m"
$HighlightOff = "`e[0m"

# Fonction pour dessiner le menu
function DessinerMenu {
    param(
        [Parameter(Mandatory=$true)]$ListeProgrammes,
        [Parameter(Mandatory=$true)]$Index
    )
    
    # Effacer l'écran pour redessiner le menu (amélioration de la clarté)
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
    
    # Définition des propriétés à afficher pour Format-Table
    $PropsAfficher = "Nom", "Version", @{Name="Taille (Mo)"; Expression={$_.TailleMo -as [string]}}, @{Name="Date d'Install."; Expression={$_.DateInstallation -ne [datetime]::MinValue ? $_.DateInstallation.ToString("yyyy-MM-dd") : "N/A"}}

    # Affichage de la liste des programmes
    for ($i = 0; $i -lt $ListeProgrammes.Count; $i++) {
        $LigneProgramme = $ListeProgrammes[$i]
        
        # Format-Table n'est pas idéal pour le surlignage ligne par ligne. 
        # On formate manuellement les colonnes pour un alignement acceptable.
        
        $Nom = ($LigneProgramme.Nom).PadRight(50)
        $Version = ($LigneProgramme.Version).PadRight(15)
        $Taille = ($LigneProgramme.TailleMo -as [string]).PadRight(10)
        $Date = if ($LigneProgramme.DateInstallation -ne [datetime]::MinValue) { 
            $LigneProgramme.DateInstallation.ToString("yyyy-MM-dd") 
        } else { "N/A" }
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

    # PowerShell trie automatiquement en ascendant si $OrdreTri est vrai
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
    # Lecture d'une touche du clavier sans afficher le caractère
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
            else { $ProprieteTri = "TailleMo"; $OrdreTri = $false } # On met Descendant par défaut pour la taille
            $ProgrammesTries = TrierListe -Programmes $Programmes
            $RedrawNeeded = $true
        }
        "D" { # Date d'installation
            if ($ProprieteTri -eq "DateInstallation") { $OrdreTri = -not $OrdreTri }
            else { $ProprieteTri = "DateInstallation"; $OrdreTri = $false } # On met Descendant par défaut pour la date
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
                # Utilisation de Start-Process pour ouvrir l'explorateur
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
            return # Sortir de la fonction et du script
        }
    }

    # Redessiner le menu si un mouvement de flèche ou un tri a eu lieu
    if ($Cle.VirtualKeyCode -in 38, 40 -or $RedrawNeeded) {
        DessinerMenu -ListeProgrammes $ProgrammesTries -Index $IndexSelection
    }
}