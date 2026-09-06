<#
.SYNOPSIS
  Tear the FinBot dev stack down and rebuild it from scratch, with no build cache.

.DESCRIPTION
  Run this whenever you want to be sure the containers reflect the code on
  disk. It stops and removes every container of the compose project,
  deletes the named node_modules volumes (they shadow the image, so a new
  dependency is otherwise invisible), removes the images compose built for
  api, worker and web, rebuilds them with --no-cache, and brings the stack
  back up.

  The database volume is kept by default so your onboarded users survive.
  Pass -WipeData to drop it too (migrations and the seed run again on boot).

.PARAMETER WipeData
  Also remove the db-data and ollama-data volumes. Everything in Postgres is
  gone; the API re-applies migrations and seeds the test user on boot.

.PARAMETER WithLlm
  Include the `llm` profile (the Ollama service) in the rebuild and the start.

.PARAMETER PullBase
  Re-pull the base images (node, postgres) during the build.

.PARAMETER NoStart
  Rebuild only; leave the stack down.

.PARAMETER DryRun
  Print the docker commands without running them.

.EXAMPLE
  .\scripts\rebuild.ps1
  .\scripts\rebuild.ps1 -WipeData
  .\scripts\rebuild.ps1 -WithLlm -PullBase
#>
[CmdletBinding()]
param(
  [switch]$WipeData,
  [switch]$WithLlm,
  [switch]$PullBase,
  [switch]$NoStart,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# The compose project lives one level above this script, whatever the
# current directory is when it runs.
$root = Split-Path -Parent $PSScriptRoot
$project = 'finbot-app'
Set-Location $root

function Invoke-Step {
  param(
    [string]$Title,
    [string[]]$Command,
    [switch]$IgnoreFailure
  )
  Write-Host ''
  Write-Host ("== {0}" -f $Title) -ForegroundColor Cyan
  Write-Host ("   > {0}" -f ($Command -join ' ')) -ForegroundColor DarkGray
  if ($DryRun) { return }

  & $Command[0] $Command[1..($Command.Length - 1)]
  if ($LASTEXITCODE -ne 0 -and -not $IgnoreFailure) {
    throw ("'{0}' exited with code {1}" -f ($Command -join ' '), $LASTEXITCODE)
  }
}

# Every compose call carries every profile, so containers started under
# `--profile llm` are torn down even when this run does not start them.
$compose = @('docker', 'compose', '--profile', 'llm')

Write-Host ("FinBot dev stack rebuild in {0}" -f $root) -ForegroundColor Green
if ($DryRun) { Write-Host '(dry run: nothing will be executed)' -ForegroundColor Yellow }

# 1. Containers and the network. Orphans are containers from services that
#    no longer exist in the compose file.
Invoke-Step -Title 'Stop and remove containers' -Command ($compose + @('down', '--remove-orphans'))

# 2. Volumes. The node_modules volumes always go: they are populated from the
#    image on first start and then shadow it forever. Data volumes only on request.
$volumes = @("${project}_api-node-modules", "${project}_web-node-modules")
if ($WipeData) { $volumes += @("${project}_db-data", "${project}_ollama-data") }
foreach ($volume in $volumes) {
  Invoke-Step -Title ("Remove volume {0}" -f $volume) -Command @('docker', 'volume', 'rm', '-f', $volume) -IgnoreFailure
}

# 3. Images compose built for this project (finbot-app-api, -worker, -web).
#    Pulled images (postgres, ollama) stay; --pull below refreshes them if asked.
$builtImages = @()
if (-not $DryRun) {
  $builtImages = @(docker images --filter "reference=$project-*" --format '{{.Repository}}:{{.Tag}}')
}
if ($builtImages.Count -gt 0) {
  Invoke-Step -Title 'Remove the images compose built' -Command (@('docker', 'image', 'rm', '-f') + $builtImages) -IgnoreFailure
} else {
  Write-Host ''
  Write-Host '== Remove the images compose built' -ForegroundColor Cyan
  Write-Host ("   > docker image rm -f <images matching {0}-*>" -f $project) -ForegroundColor DarkGray
}

# 4. Rebuild with no layer cache.
$build = @('build', '--no-cache')
if ($PullBase) { $build += '--pull' }
$services = @('api', 'worker', 'web')
if ($WithLlm) {
  Invoke-Step -Title 'Rebuild images (no cache)' -Command ($compose + $build)
} else {
  Invoke-Step -Title 'Rebuild images (no cache)' -Command (@('docker', 'compose') + $build + $services)
}

# 5. Bring it back.
if ($NoStart) {
  Write-Host ''
  Write-Host 'Rebuilt. The stack is down (-NoStart); start it with: docker compose up -d' -ForegroundColor Green
  exit 0
}

$up = @('up', '-d', '--force-recreate')
if ($WithLlm) {
  Invoke-Step -Title 'Start the stack (with Ollama)' -Command ($compose + $up)
} else {
  Invoke-Step -Title 'Start the stack' -Command (@('docker', 'compose') + $up)
}

Invoke-Step -Title 'Status' -Command @('docker', 'compose', 'ps') -IgnoreFailure

Write-Host ''
Write-Host 'Done. The api applies migrations on boot; follow it with:' -ForegroundColor Green
Write-Host '   docker compose logs -f api worker' -ForegroundColor DarkGray
if ($WipeData) {
  Write-Host 'Data was wiped: the seed user is back, onboarded users are gone.' -ForegroundColor Yellow
}
