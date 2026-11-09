param(
  [Parameter(Mandatory = $true)]
  [string]$Username
)

$ErrorActionPreference = "Stop"

$repos = @("codearena", "codearena-frontend", "codearena-backend")

foreach ($repo in $repos) {
  Write-Host "Inviting $Username to $repo"
  gh repo add-collaborator $repo $Username --permission push
}

Write-Host "Invited $Username to all three repositories with push access."
Write-Host "Access to the parent alone does not include the frontend or backend."
