& 'C:\BuildTools\Common7\Tools\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64
if ($args.Count -gt 0) {
    & $args[0] $args[1..($args.Count-1)]
    exit $LASTEXITCODE
} else {
    msbuild /?
}
