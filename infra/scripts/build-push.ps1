# Build and push all three service images to ECR (TASK-1 §2).
# Run from repo root:  .\infra\scripts\build-push.ps1   (Windows PowerShell 5 or pwsh)
# Requires: Docker running, AWS CLI v2, SSO: aws sso login --profile Devan

$ErrorActionPreference = "Stop"
$Region = "us-east-1"
$Prefix = "hackthon-k9-intern-devan"
$Profile = "Devan"

$Account = (aws sts get-caller-identity --profile $Profile --query Account --output text)
if (-not $Account) { throw "AWS CLI login failed (try: aws sso login --profile $Profile)" }

$Registry = "$Account.dkr.ecr.$Region.amazonaws.com"

# Clear stale Docker creds for this registry (fixes "400 Bad Request" / no basic auth).
docker logout $Registry 2>$null

# PowerShell pipeline to docker login is flaky on Windows; cmd.exe pipe matches AWS docs reliably.
$loginCmd = "aws ecr get-login-password --region $Region --profile $Profile | docker login --username AWS --password-stdin $Registry"
cmd /c $loginCmd
if ($LASTEXITCODE -ne 0) {
    throw @"
ECR docker login failed (exit $LASTEXITCODE).
Fix:  aws sso login --profile $Profile
Then: aws ecr get-login-password --region $Region --profile $Profile | docker login --username AWS --password-stdin $Registry
If it still returns 400: Docker Desktop -> Sign out of other registries; ensure Docker is using linux engine for builds.
"@
}

# infra/scripts -> repo root (hackathon-intern)
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $Root

foreach ($svc in @("main-backend", "extractor", "parser")) {
  $repo = "$Registry/$Prefix-$svc-ecr"
  Write-Host "Building $svc -> $repo`:latest"
  docker build -t "$repo`:latest" "./$svc"
  docker push "$repo`:latest"
}

Write-Host "Done. Force ECS redeploy if tasks were already running."
