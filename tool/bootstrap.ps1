<#
.SYNOPSIS
    Fills in the machine-generated platform files that are not kept in source control.

.DESCRIPTION
    The hand-written platform configuration (AndroidManifest.xml, build.gradle,
    Info.plist, AppDelegate.swift, Podfile, ...) lives in this repository. The
    purely generated artefacts (Xcode project file, Gradle wrapper jar, launcher
    icons, storyboards, GeneratedPluginRegistrant) are not, because they are
    reproducible and noisy in diffs.

    This script materialises them by running `flutter create` into a temporary
    directory and copying across only the files that are MISSING here. Existing
    files are never overwritten, so the curated configuration is safe.

.EXAMPLE
    pwsh tool/bootstrap.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipPubGet
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$template = Join-Path ([System.IO.Path]::GetTempPath()) "voice_reminder_template_$([guid]::NewGuid().ToString('N'))"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'flutter was not found on PATH. Install the Flutter SDK first: https://docs.flutter.dev/get-started/install'
}

Write-Host "Generating platform template in $template ..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path $template -Force | Out-Null

& flutter create --platforms=android,ios --org com.voicereminder --project-name voice_reminder $template
if ($LASTEXITCODE -ne 0) { throw "flutter create failed with exit code $LASTEXITCODE" }

$copied = 0
$skipped = 0
$rejected = 0

# Files the template generates that would CONFLICT with this project's curated
# configuration rather than merely duplicate it. Current Flutter templates emit
# Kotlin-DSL Gradle files; this project uses the Groovy DSL, and Gradle picking
# whichever it finds first would silently discard the desugaring, signing and
# SDK settings. The template's MainActivity also lands in the wrong package.
$conflicts = @(
    'android\build.gradle.kts',
    'android\settings.gradle.kts',
    'android\app\build.gradle.kts',
    'android\app\src\main\kotlin\com\voicereminder\voice_reminder\MainActivity.kt'
)

# Only the platform folders are of interest; lib/ and test/ are fully authored here.
foreach ($folder in @('android', 'ios')) {
    $sourceRoot = Join-Path $template $folder
    if (-not (Test-Path $sourceRoot)) { continue }

    Get-ChildItem -Path $sourceRoot -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($template.Length).TrimStart('\', '/')
        $destination = Join-Path $projectRoot $relative

        if ($conflicts -contains $relative -or $relative -like '*.iml') {
            $rejected++
            return
        }

        if (Test-Path $destination) {
            $skipped++
            return
        }

        $destinationDir = Split-Path -Parent $destination
        if (-not (Test-Path $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }
        Copy-Item -Path $_.FullName -Destination $destination
        $copied++
        Write-Host "  + $relative" -ForegroundColor DarkGray
    }
}

Remove-Item -Path $template -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ("Bootstrap complete: $copied added, $skipped preserved, " +
    "$rejected rejected as conflicting.") -ForegroundColor Green

if (-not $SkipPubGet) {
    Write-Host 'Running flutter pub get ...' -ForegroundColor Cyan
    Push-Location $projectRoot
    try {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed with exit code $LASTEXITCODE" }

        Write-Host 'Running build_runner (Drift + Riverpod code generation) ...' -ForegroundColor Cyan
        & dart run build_runner build --delete-conflicting-outputs
        if ($LASTEXITCODE -ne 0) { throw "build_runner failed with exit code $LASTEXITCODE" }
    }
    finally {
        Pop-Location
    }
}

Write-Host 'Ready. Run `flutter run` to launch the app.' -ForegroundColor Green
