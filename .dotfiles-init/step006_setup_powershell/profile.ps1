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

function Invoke-LinuxLikeSSHCopyId {
    [CmdletBinding()]
    param (
        [Alias("i")]
        [Parameter(Mandatory = $true)]
        [string]$PubKeyPath,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$SSHParams,
        [Parameter(Mandatory = $true)]
        [string[]]$Destination
    )
    $content = (Get-Content -Path "${PubKeyPath}" -ErrorAction Stop) -replace "`r?`n", ""
    $command = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && printf '%s\n' '${content}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    ssh ${SSHParams} "${Destination}" "${command}"
}

chcp 65001

Set-PSReadLineOptions

New-Alias -Name ssh-copy-id -Value Invoke-LinuxLikeSSHCopyId -Option AllScope

""
"==============================================================================="
"    Profile created by 03hcl/dotfiles (https://github.com/03hcl/dotfiles/)"
"==============================================================================="
""
