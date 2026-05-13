Write-Host "hello from claude via runner"
Write-Host "ps version: $($PSVersionTable.PSVersion)"
Write-Host "pwd: $(Get-Location)"
Write-Host "git: $(git --version)"
Write-Host "dotnet: $(dotnet --version)"
Write-Host "smoke test ok" -ForegroundColor Green
exit 0
