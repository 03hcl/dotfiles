#!/usr/bin/env pwsh

function Update-PSReadLineOptions {
    if (-not (Get-Module -Name PSReadLine)) { Import-Module PSReadLine }

    # Reference:
    #   https://learn.microsoft.com/ja-jp/powershell/module/psreadline/set-psreadlineoption
    $options = @{
        EditMode                      = "Emacs"
        # EditMode                      = "Windows"
        HistoryNoDuplicates           = $true
        HistorySearchCursorMovesToEnd = $true
        MaximumHistoryCount           = 10000
    }
    Set-PSReadLineOption @options

    # Reference:
    #   https://learn.microsoft.com/ja-jp/powershell/scripting/learn/shell/using-keyhandlers
    Set-PSReadLineKeyHandler -Key Ctrl+d -Function DeleteCharOrExit
    Set-PSReadLineKeyHandler -Key Ctrl+v -Function Paste
    Set-PSReadLineKeyHandler -Key Ctrl+LeftArrow -Function BackwardWord
    Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function ForwardWord
}

function Update-ProfileAlias {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Alias,

        [Parameter(Mandatory = $true)]
        [string]$Function
    )
    if (Get-Command -Name "${Alias}" -CommandType Function -ErrorAction SilentlyContinue) { return }

    # if (Get-Alias -Name "${Alias}" -ErrorAction SilentlyContinue) { Remove-Item Alias:"${Alias}" -Force -ErrorAction SilentlyContinue }
    New-Alias -Name "${Alias}" -Value "${Function}" -Scope Global -Force
    # Set-Alias -Name "${Alias}" -Value "${Function}" -Scope Global -Force
}

###############################################################################

$__profileHelpFlags = @("-h", "-?", "--help", "/?")
$__profileVersion = "version 0.2.0 (2026-11-10)"
$__profileVersionFlags = @("-V", "--version")

function Invoke-LinuxLikeSSHCopyId {
    [CmdletBinding(PositionalBinding = $false)]
    param (
        [Alias("f")]
        [switch]$Force,

        [Alias("n")]
        [switch]$DryRun,

        # [Alias("s")]
        # [string]$UseSftp,

        # [Alias("x")]
        # [string]$Debug,

        [Alias("i")]
        [string]$IdentityFilePath,

        [Alias("p")]
        [string]$Port,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$SSHParams,

        [Alias("h", "?")]
        [switch]$Help,

        [Alias("V")]
        [switch]$Version
    )
    if (${Help} -or (${SSHParams} | Where-Object { ${__profileHelpFlags} -contains $_ })) {
        ""
        "[POWERED BY 'profiles.ps1' (CREATED BY 03hcl/dotfiles)]"
        ""
        "Usage:"
        "  <Invoke-LinuxLikeSSHCopyId>|<ssh-copy-id> [-f|-n|-h|-?|-V] -i <identity_file> [-p <port>] [-- <ssh options> ...] <[user@]hostname>"
        ""
        "Arguments:"
        "  <[user@]hostname>     destination host (required, must be the last argument)"
        ""
        "Options:"
        "  -f                    force mode: copy keys without trying to check if they are already installed"
        "  -n                    dry run: no keys are actually copied"
        # "  -s                    use sftp: use sftp instead of executing remote-commands. Can be useful if the remote only allows sftp"
        # "  -x                    debug: enables -x in this shell, for debugging"
        "  -i <identity_file>    path to identity file (required, '.pub' is appended if missing)"
        "  -p <port>             port to connect to on the remote host"
        # ""
        "  -- <ssh options>      other ssh options passed as is"
        ""
        "  -h, --help, /?        print this help"
        "  -V                    print version"
        ""
        return
    }
    if (${Version} -or (${SSHParams} | Where-Object { ${__profileVersionFlags} -contains $_ })) {
        "${__profileVersion}"
        return
    }

    if (-not ${IdentityFilePath}.EndsWith(".pub", [System.StringComparison]::OrdinalIgnoreCase)) { $IdentityFilePath = "${IdentityFilePath}.pub" }

    $lines = @(Get-Content -Path "${IdentityFilePath}" -Encoding UTF8 -ErrorAction Stop | Where-Object { $_ })
    $commands = @(
        "cd"
        "umask 077"
        "mkdir -p .ssh"
        "if command -v restorecon >/dev/null 2>&1; then restorecon -R .ssh; fi"
        'if [ -s .ssh/authorized_keys ] && [ $(tail -c 1 .ssh/authorized_keys | wc -l) -eq 0 ]; then echo >> .ssh/authorized_keys; fi'

        foreach ($line in $lines) {
            $pubkey = (-split ${line})[1]
            if (${pubkey} -notmatch '^[A-Za-z0-9+/=]+$') { throw "Invalid public key: ${line}" }

            $octalLine = -join ([System.Text.Encoding]::UTF8.GetBytes("${line}`n") | ForEach-Object { '\' + [System.Convert]::ToString($_, 8) })
            if (${Force}) { "printf '${octalLine}' >> .ssh/authorized_keys" }
            else { "(grep -qF ${pubkey} .ssh/authorized_keys 2>/dev/null || printf '${octalLine}' >> .ssh/authorized_keys)" }
        }

        "if command -v restorecon >/dev/null 2>&1; then restorecon -R .ssh; fi"
    )

    $options = @(
        if (${Port}) {
            "-p"
            "${Port}"
        }
        ${SSHParams}
        ("exec sh -c '" + ((${commands} -join ' && ') -replace "'", "'\''") + "'")
    )

    if (${DryRun}) { '"ssh" "' + (${options} -join '" "') + '"' }
    else { ssh @options }
}

function Lock-File {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [string]$Path,

        [Alias("s")]
        [switch]$Shared,

        # Not used, for compatibility
        [Alias("x")]
        [switch]$Exclusive,

        [Alias("u")]
        [switch]$Unlock,

        # [Alias("n")]
        # [switch]$NonBlock,

        # [Alias("w")]
        # [double]$Timeout = 0,

        [Alias("E")]
        [ValidateRange(0, 255)]
        [int]$ConflictExitCode = 1,

        [Alias("c")]
        [scriptblock]$Command,

        [Alias("h", "?")]
        [switch]$Help,

        [Alias("V")]
        [switch]$Version
    )
    $params = @(${PSBoundParameters}.Values | ForEach-Object { $_.ToString() })
    if (${Help} -or (${params} | Where-Object { ${__profileHelpFlags} -contains $_ })) {
        ""
        "[POWERED BY 'profiles.ps1' (CREATED BY 03hcl/dotfiles)]"
        ""
        "Usage:"
        "  <Lock-File>|<flock> [options] <file>|<directory> <command> [<argument>...]"
        "  <Lock-File>|<flock> [options] <file>|<directory> -c <command>"
        ""
        "Manage file locks from shell scripts."
        ""
        "Options:"
        "  -s                    get a shared lock"
        "  -x                    get an exclusive lock (default)"
        "  -u                    remove a lock"
        "  -n                    fail rather than wait"
        # "  -w <secs>             wait for a limited amount of time"
        "  -E <number>           exit code after conflict (default: 1)"
        # "  -o                    close file descriptor before running command"
        # "  -c <command>          run a single command scriptblock"
        # "  -F                    execute command without forking"
        # "  -v                    increase verbosity"
        ""
        "  -h, --help, /?        display this help"
        "  -V, --version         display version"
        ""
        return
    }
    if (${Version} -or (${params} | Where-Object { ${__profileVersionFlags} -contains $_ })) { "${__profileVersion}"; return }

    # if (${Timeout} -eq 0) { $NonBlock = $true }

    if (${Unlock}) {
        throw "Unlocking is not supported."
    }

    if (-not ${Shared}) {
        $access = [System.IO.FileAccess]::ReadWrite
        $share = [System.IO.FileShare]::None
    } else {
        $access = [System.IO.FileAccess]::Read
        $share = [System.IO.FileShare]::Read
    }

    $mode = [System.IO.FileMode]::OpenOrCreate
    # $mode = [System.IO.FileMode]::Open
    $fs = & { try { [System.IO.File]::Open(${Path}, ${mode}, ${access}, ${share}) } catch { $null } }

    if (-not ${fs}) {
        ${global:LASTEXITCODE} = ${ConflictExitCode}
        return $null
    }

    if (${Command}) {
        # FIXME: LASTEXITCODE not set correctly
        try { return & ${Command} }
        finally { ${fs}.Dispose() }
    }

    return ${fs}
}

###############################################################################

chcp 65001

Update-PSReadLineOptions
Update-ProfileAlias flock Lock-File
Update-ProfileAlias ssh-copy-id Invoke-LinuxLikeSSHCopyId

""
"==============================================================================="
"    Profile created by 03hcl/dotfiles (https://github.com/03hcl/dotfiles/)"
"==============================================================================="
""
