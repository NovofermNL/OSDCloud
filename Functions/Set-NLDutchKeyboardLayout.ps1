function Set-NLDutchKeyboardLayout {
    <#
    .SYNOPSIS
    Stelt de invoertaal in op Nederlands (Nederland) met het toetsenbord US-International.

    .DESCRIPTION
    Deze functie verwijdert alle andere talen behalve 'nl-NL' en stelt de invoermethode in op US-International (00020409).

    .EXAMPLE
    Set-NLDutchKeyboardLayout
    # Past de taalinstellingen toe voor de huidige gebruiker.
    #>

    [CmdletBinding()]
    param()

    try {
        # Huidige taallijst ophalen
        $langList = Get-WinUserLanguageList

        # Controleren of nl-NL al aanwezig is, anders toevoegen
        if (-not ($langList.LanguageTag -contains "nl-NL")) {
            Write-Verbose "nl-NL niet gevonden, wordt toegevoegd..."
            $langList.Add((New-WinUserLanguageList -LanguageTag "nl-NL"))
        }

        # Alleen nl-NL behouden
        $langList = $langList | Where-Object { $_.LanguageTag -eq "nl-NL" }

        # Input methods wissen en enkel US-International toevoegen
        $langList[0].InputMethodTips.Clear()
        $langList[0].InputMethodTips.Add("0413:00020409")

        # Nieuwe instellingen toepassen
        Set-WinUserLanguageList $langList -Force

        Write-Output "De invoertaal is ingesteld op Nederlands (Nederland) met US-International toetsenbord."
    }
    catch {
        Write-Error "Er is een fout opgetreden: $_"
    }
}
