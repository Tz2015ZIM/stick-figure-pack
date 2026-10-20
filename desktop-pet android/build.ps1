# build.ps1
# Builds DesktopStickman.apk with nothing but the JDK and the Android SDK's
# command-line pieces: no Android Studio, no Gradle.
#
#   powershell -ExecutionPolicy Bypass -File build.ps1           build the APK
#   powershell -ExecutionPolicy Bypass -File build.ps1 -Test     also run him on the PC first (tools\Preview.java)
#
# It looks for the SDK in $env:ANDROID_HOME, then ~\AndroidBuild\sdk, and for
# the JDK in $env:JAVA_HOME, then ~\AndroidBuild\jdk. It signs with
# stickman.keystore, made the first time: keep that file, since a phone only
# installs an update over him if it is signed with the same key.

param([switch]$Test)

$ErrorActionPreference = 'Stop'
$here  = $PSScriptRoot
$tools = Join-Path $env:USERPROFILE 'AndroidBuild'

$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $tools 'sdk' }
$jdk = if ($env:JAVA_HOME) { $env:JAVA_HOME } else {
    (Get-ChildItem (Join-Path $tools 'jdk') -Directory | Select-Object -First 1).FullName
}
$env:JAVA_HOME = $jdk
$env:Path = (Join-Path $jdk 'bin') + ';' + $env:Path

$bt = (Get-ChildItem (Join-Path $sdk 'build-tools') -Directory | Sort-Object { [version]($_.Name -replace '[^\d.]', '') } |
       Select-Object -Last 1).FullName
$jar = Join-Path $sdk 'platforms\android-36\android.jar'
foreach ($p in @($bt, $jar, (Join-Path $jdk 'bin\javac.exe'))) {
    if (-not $p -or -not (Test-Path $p)) { throw "Missing: $p (see README.md, Building)" }
}

$out = Join-Path $here 'build'
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force -Path "$out\gen", "$out\classes", "$out\dex" | Out-Null

# runs a tool with an array of arguments, so PowerShell leaves them alone
function Run([string]$exe, [string[]]$a) {
    & $exe @a
    if ($LASTEXITCODE -ne 0) { throw "$(Split-Path -Leaf $exe) failed ($LASTEXITCODE)" }
}

$sources = @(Get-ChildItem (Join-Path $here 'src') -Recurse -Filter *.java | ForEach-Object { $_.FullName })

if ($Test) {
    # the stickmen on a plain JVM: every pose into a PNG, then a few thousand
    # frames of them getting on with life and with a fight
    Write-Host 'Testing on the PC...'
    $pv = Join-Path $out 'preview'
    New-Item -ItemType Directory -Force -Path "$pv\classes" | Out-Null
    $core = @($sources | Where-Object { (Get-Content $_ -Raw) -notmatch 'import android\.' })
    Run 'javac' (@('-nowarn', '-encoding', 'UTF-8', '-d', "$pv\classes") + $core + @(Join-Path $here 'tools\Preview.java'))
    Run 'java' @('-cp', "$pv\classes", 'com.desktopstickman.Preview', $pv)
    Write-Host "Pictures in $pv"
}

Write-Host 'Resources...'
$aapt2 = Join-Path $bt 'aapt2.exe'
Run $aapt2 @('compile', '--dir', (Join-Path $here 'res'), '-o', "$out\res.zip")
Run $aapt2 @('link', '-o', "$out\unsigned.apk", '-I', $jar, '--manifest', (Join-Path $here 'AndroidManifest.xml'),
             '--java', "$out\gen", '--min-sdk-version', '26', '--target-sdk-version', '36', "$out\res.zip")

Write-Host 'Java...'
$gen = @(Get-ChildItem "$out\gen" -Recurse -Filter *.java | ForEach-Object { $_.FullName })
# Java 8 language, which d8 turns into what every phone from Android 8 on
# runs; the lambda stubs stand in for the JDK classes lambdas compile against
$boot = $jar + ';' + (Join-Path $bt 'core-lambda-stubs.jar')
Run 'javac' (@('-nowarn', '-encoding', 'UTF-8', '-source', '8', '-target', '8', '-Xlint:-options',
               '-bootclasspath', $boot, '-d', "$out\classes") + $sources + $gen)

Write-Host 'Dex...'
$classes = @(Get-ChildItem "$out\classes" -Recurse -Filter *.class | ForEach-Object { $_.FullName })
Run (Join-Path $bt 'd8.bat') (@('--release', '--min-api', '26', '--lib', $jar, '--output', "$out\dex") + $classes)

Write-Host 'APK...'
Push-Location "$out\dex"
try { Run (Join-Path $bt 'aapt.exe') @('add', "$out\unsigned.apk", 'classes.dex') | Out-Null } finally { Pop-Location }
Run (Join-Path $bt 'zipalign.exe') @('-p', '-f', '4', "$out\unsigned.apk", "$out\aligned.apk")

$ks = Join-Path $here 'stickman.keystore'
if (-not (Test-Path $ks)) {
    Write-Host 'Making stickman.keystore (keep it: updates need the same key)...'
    Run 'keytool' @('-genkeypair', '-keystore', $ks, '-alias', 'stickman', '-keyalg', 'RSA', '-keysize', '2048',
                    '-validity', '10000', '-storepass', 'stickman', '-keypass', 'stickman', '-dname', 'CN=Desktop Stickman')
}
$apk = Join-Path $here 'DesktopStickman.apk'
$signer = Join-Path $bt 'apksigner.bat'
Run $signer @('sign', '--ks', $ks, '--ks-pass', 'pass:stickman', '--key-pass', 'pass:stickman', '--out', $apk, "$out\aligned.apk")
Run $signer @('verify', $apk)
Write-Host "Built $apk"
