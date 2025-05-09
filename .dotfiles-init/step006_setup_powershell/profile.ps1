#!/usr/bin/env pwsh

function Set-PSReadLineOptions {
    if (-not (Get-Module -Name PSReadLine)) { Import-Module PSReadLine }

    # Reference:
    #   https://learn.microsoft.com/ja-jp/powershell/module/psreadline/set-psreadlineoption
    $options = @{
        EditMode = "Emacs"
        # EditMode = "Windows"
        HistoryNoDuplicates = $true
        HistorySearchCursorMovesToEnd = $true
        MaximumHistoryCount = 10000
    }
    Set-PSReadLineOption @options

    # Reference:
    #   https://learn.microsoft.com/ja-jp/powershell/scripting/learn/shell/using-keyhandlers
    Set-PSReadLineKeyHandler -Key Ctrl+d -Function DeleteCharOrExit
    Set-PSReadLineKeyHandler -Key Ctrl+v -Function Paste
    Set-PSReadLineKeyHandler -Key Ctrl+LeftArrow -Function BackwardWord
    Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function ForwardWord
}

chcp 65001

Set-PSReadLineOptions

""
"==============================================================================="
"    Profile created by 03hcl/dotfiles (https://github.com/03hcl/dotfiles/)"
"==============================================================================="
""
