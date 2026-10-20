<#
バルカン連邦 MOD：Python が無い Windows 環境向けの生成スクリプト。
Python 版 (generate_from_game.py) と同じことをする。

使い方（PowerShell）:
  Set-ExecutionPolicy -Scope Process Bypass
  .\tools\generate_from_game.ps1 "C:\Program Files (x86)\Steam\steamapps\common\Hearts of Iron IV"
#>
param([Parameter(Mandatory=$true)][string]$GameDir)

$ErrorActionPreference = "Stop"
$ModRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$OldTags = @("YUG","BUL","ALB")
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)

function Read-Text($p) { [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }
function Write-Text($p, $t) {
  $dir = Split-Path -Parent $p
  if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  [System.IO.File]::WriteAllText($p, $t, $Utf8Bom)
}
function Strip-Comments($t) { [regex]::Replace($t, "#.*", "") }

function Get-BlockEnd($t, $start) {
  $depth = 1; $i = $start
  while ($i -lt $t.Length -and $depth -gt 0) {
    $c = $t[$i]
    if ($c -eq '{') { $depth++ } elseif ($c -eq '}') { $depth-- }
    $i++
  }
  return $i - 1
}

function Get-DatedSpans($body) {
  $spans = @()
  foreach ($m in [regex]::Matches($body, "\b\d{4}\.\d{1,2}\.\d{1,2}\s*=\s*\{")) {
    $e = Get-BlockEnd $body ($m.Index + $m.Length)
    $spans += ,@($m.Index, $e)
  }
  return $spans
}
function In-Spans($pos, $spans) {
  foreach ($s in $spans) { if ($pos -ge $s[0] -and $pos -lt $s[1]) { return $true } }
  return $false
}
function Replace-Outside($s, $pattern, $repl) {
  $cl = Strip-Comments $s
  $spans = Get-DatedSpans $cl
  $sb = New-Object System.Text.StringBuilder
  $last = 0
  foreach ($m in [regex]::Matches($s, $pattern)) {
    if (In-Spans $m.Index $spans) { continue }
    [void]$sb.Append($s.Substring($last, $m.Index - $last))
    [void]$sb.Append($m.Result($repl))
    $last = $m.Index + $m.Length
  }
  [void]$sb.Append($s.Substring($last))
  return $sb.ToString()
}

# ---- 1. states ----
$n = 0
Get-ChildItem (Join-Path $GameDir "history\states\*.txt") | ForEach-Object {
  $text = Read-Text $_.FullName
  $m = [regex]::Match($text, "\bhistory\s*=\s*\{")
  if (!$m.Success) { return }
  $bstart = $m.Index + $m.Length
  $bend = Get-BlockEnd $text $bstart
  $body = $text.Substring($bstart, $bend - $bstart)
  $clean = Strip-Comments $body
  $spans = Get-DatedSpans $clean
  $owner = $null
  foreach ($om in [regex]::Matches($clean, "\bowner\s*=\s*([A-Z]{3})")) {
    if (!(In-Spans $om.Index $spans)) { $owner = $om.Groups[1].Value; break }
  }
  if ($OldTags -notcontains $owner) { return }
  $nb = Replace-Outside $body "\bowner\s*=\s*(YUG|BUL|ALB)\b" "owner = BLK`n`t`tadd_core_of = BLK"
  $nb = Replace-Outside $nb "\bcontroller\s*=\s*(YUG|BUL|ALB)\b" "controller = BLK"
  $nb = [regex]::Replace($nb, "\b(owner|controller)\s*=\s*(YUG|BUL|ALB)\b", '$1 = BLK')
  $out = "# バルカン連邦 MOD による上書き（generate_from_game.ps1 が生成）`n# 元の所有者: $owner`n" + $text.Substring(0,$bstart) + $nb + $text.Substring($bend)
  Write-Text (Join-Path $ModRoot ("history\states\" + $_.Name)) $out
  $script:n++
}
Write-Host "states overridden: $n"

# ---- 2. countries ----
foreach ($tag in $OldTags) {
  Get-ChildItem (Join-Path $GameDir ("history\countries\" + $tag + " - *.txt")) | ForEach-Object {
    $text = Read-Text $_.FullName
    $text = [regex]::Replace($text, "(?m)^(\s*)(oob|set_naval_oob|set_air_oob)\s*=", '$1# [BLK] $2 =')
    Write-Text (Join-Path $ModRoot ("history\countries\" + $_.Name)) ("# バルカン連邦 MOD による上書き：$tag は 1936 年に連邦へ統合済み`n" + $text)
    Write-Host ("country overridden: " + $_.Name)
  }
}

# ---- 3. OOB ----
$cityStates = @{ "@BELGRADE"=107; "@KRAGUJEVAC"=107; "@NIS"=108; "@NOVI_SAD"=45; "@SOFIA"=48; "@PLOVDIV"=212; "@PLEVEN"=801; "@VARNA"=211;
                 "@ZAGREB"=109; "@LJUBLJANA"=102; "@SARAJEVO"=104; "@SKOPJE"=106; "@CETINJE"=105; "@TIRANA"=44; "@SPLIT"=103 }
$vps = @{}
Get-ChildItem (Join-Path $GameDir "history\states\*.txt") | ForEach-Object {
  $t = Strip-Comments (Read-Text $_.FullName)
  $idm = [regex]::Match($t, "\bid\s*=\s*(\d+)")
  if (!$idm.Success) { return }
  $sid = [int]$idm.Groups[1].Value
  $list = @()
  foreach ($vm in [regex]::Matches($t, "victory_points\s*=\s*\{\s*(\d+)\s+(\d+)\s*\}")) { $list += ,@([int]$vm.Groups[2].Value, [int]$vm.Groups[1].Value) }
  if ($list.Count -eq 0) {
    $pm = [regex]::Match($t, "provinces\s*=\s*\{([^}]*)\}")
    if ($pm.Success) { $ids = $pm.Groups[1].Value -split "\s+" | Where-Object { $_ -ne "" }; if ($ids.Count -gt 0) { $list += ,@(0, [int]$ids[0]) } }
  }
  $vps[$sid] = $list | Sort-Object { $_[0] } -Descending
}
$tmpl = Read-Text (Join-Path $ModRoot "tools\BLK_1936.oob.template")
foreach ($ph in $cityStates.Keys) {
  $sid = $cityStates[$ph]
  $lst = $vps[$sid]
  if ($null -eq $lst -or $lst.Count -eq 0) { Write-Host "warning: no province for $ph"; $prov = ($vps[107] | Select-Object -First 1)[1] }
  else {
    $idx = 0
    if ($ph -eq "@KRAGUJEVAC" -and $lst.Count -gt 1) { $idx = 1 }
    $prov = ($lst | Select-Object -Index $idx)[1]
  }
  $tmpl = $tmpl.Replace($ph, [string]$prov)
}
$wings = @()
foreach ($tag in $OldTags) {
  $p = Join-Path $GameDir ("history\units\" + $tag + "_1936.txt")
  if (!(Test-Path $p)) { continue }
  $t = Read-Text $p
  $m = [regex]::Match($t, "\bair_wings\s*=\s*\{")
  if (!$m.Success) { continue }
  $s = $m.Index + $m.Length; $e = Get-BlockEnd $t $s
  $inner = $t.Substring($s, $e - $s)
  $inner = [regex]::Replace($inner, 'owner\s*=\s*"?(YUG|BUL|ALB)"?', 'owner = "BLK"')
  $wings += "`t# from $tag`n$inner"
}
if ($wings.Count -gt 0) { $tmpl += "`nair_wings = {`n" + ($wings -join "`n") + "`n}`n" }
Write-Text (Join-Path $ModRoot "history\units\BLK_1936.txt") $tmpl
Write-Host "wrote history/units/BLK_1936.txt"

# ---- 4. navy ----
$hasMtg = $false; $hasLegacy = $false
foreach ($suffix in @("_naval_mtg","_naval_legacy","_naval")) {
  $blocks = @()
  foreach ($tag in $OldTags) {
    $p = Join-Path $GameDir ("history\units\" + $tag + "_1936" + $suffix + ".txt")
    if (!(Test-Path $p)) { continue }
    $t = Read-Text $p
    $m = [regex]::Match($t, "\bunits\s*=\s*\{")
    if (!$m.Success) { continue }
    $s = $m.Index + $m.Length; $e = Get-BlockEnd $t $s
    $inner = $t.Substring($s, $e - $s)
    $inner = [regex]::Replace($inner, 'owner\s*=\s*"?(YUG|BUL|ALB)"?', 'owner = BLK')
    $blocks += "`t# from $tag`n$inner"
  }
  if ($blocks.Count -gt 0) {
    Write-Text (Join-Path $ModRoot ("history\units\BLK_1936" + $suffix + ".txt")) ("# バルカン連邦 海軍編成`nunits = {`n" + ($blocks -join "`n") + "`n}`n")
    Write-Host ("wrote history/units/BLK_1936" + $suffix + ".txt")
    if ($suffix -eq "_naval_mtg") { $hasMtg = $true }
    if ($suffix -eq "_naval_legacy") { $hasLegacy = $true }
  }
}
$hist = Join-Path $ModRoot "history\countries\BLK - Balkan Federation.txt"
$ht = Read-Text $hist
if (($hasMtg -or $hasLegacy) -and ($ht -notmatch "set_naval_oob")) {
  $add = "`n# 海軍編成（generate_from_game.ps1 が追記）`n"
  if ($hasMtg -and $hasLegacy) { $add += "if = {`n`tlimit = { has_dlc = `"Man the Guns`" }`n`tset_naval_oob = `"BLK_1936_naval_mtg`"`n}`nelse = {`n`tset_naval_oob = `"BLK_1936_naval_legacy`"`n}`n" }
  elseif ($hasMtg) { $add += "set_naval_oob = `"BLK_1936_naval_mtg`"`n" }
  else { $add += "set_naval_oob = `"BLK_1936_naval_legacy`"`n" }
  Write-Text $hist ($ht + $add)
  Write-Host "patched BLK history with naval oob"
}
Write-Host "done."
