$paths = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
         "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"

$paths | ForEach-Object {
    Get-ChildItem $_ | ForEach-Object {
        [PSCustomObject]@{
            Nom = $_.GetValue("DisplayName")
            Version = $_.GetValue("DisplayVersion")
        }
    }
} | Where-Object { $_.Nom } | Sort-Object Nom | Format-Table -AutoSize
