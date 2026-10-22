param(
    [switch]$NoUI,
    [switch]$InitializeKey,
    [switch]$UISmokeTest,
    [string]$PreviewPath,
    [string]$HistoryPreviewPath,
    [double]$PreviewScale = 1,
    [string]$DataDirectory = (Join-Path $PSScriptRoot 'private'),
    [string]$PublicKeyFile = (Join-Path $PSScriptRoot 'GlassFolders-public.txt'),
    [string]$PublicHeader
)
$ErrorActionPreference = 'Stop'
if (-not ('GFCrypto' -as [type])) {
    if ($PSVersionTable.PSEdition -eq 'Core') {
        Add-Type -Path (Join-Path $PSScriptRoot 'GFCrypto.cs')
    } else {
        Add-Type -Path (Join-Path $PSScriptRoot 'GFCrypto.cs') -ReferencedAssemblies System.Security.dll
    }
}
$script:GFData = [IO.Path]::GetFullPath($DataDirectory)
$script:GFPublicFile = [IO.Path]::GetFullPath($PublicKeyFile)
$script:GFKeyFile = Join-Path $script:GFData 'issuer-key.dpapi'
$script:GFStateFile = Join-Path $script:GFData 'records.json'
$script:GFUtf8 = New-Object Text.UTF8Encoding($false, $true)
# Single writer: do not allow two windows to overwrite challenge/record state.
$script:GFDataLock = $null
function Open-GFData {
    if ($script:GFDataLock) { return }
    [IO.Directory]::CreateDirectory($script:GFData) | Out-Null
    try {
        $script:GFDataLock = [IO.File]::Open((Join-Path $script:GFData 'issuer.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    } catch { throw 'Another issuer is using this data folder. Close that window first.' }
}
function Write-GFAtomic([string]$Path, [string]$Text) {
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, $Text, $script:GFUtf8)
        if ([IO.File]::Exists($Path)) { [IO.File]::Copy($Path, $Path + '.backup', $true) }
        [GFCrypto]::AtomicReplace($temporary, $Path)
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
function Get-GFState {
    Open-GFData
    if (-not [IO.File]::Exists($script:GFStateFile)) { return [pscustomobject]@{ Challenges = @(); Licenses = @() } }
    # Fail closed on corrupt state; never silently reset consumed challenges.
    $state = [IO.File]::ReadAllText($script:GFStateFile, $script:GFUtf8) | ConvertFrom-Json
    if ($null -eq $state.Challenges -or $null -eq $state.Licenses) { throw 'Invalid issuer records.' }
    return $state
}
function Save-GFState($State) { Write-GFAtomic $script:GFStateFile ($State | ConvertTo-Json -Depth 8) }
# Parsing a Z-suffixed DateTime converts it to local time in Windows PowerShell.
# Subtracting that local epoch from UtcNow shifts every challenge by the timezone.
function Get-GFNow { return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function ConvertTo-GF64([byte[]]$Bytes) { return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+','-').Replace('/','_') }
function ConvertFrom-GF64([string]$Text) {
    if ($Text -cnotmatch '^[A-Za-z0-9_-]+$' -or $Text.Length % 4 -eq 1) { throw 'Invalid Base64URL.' }
    $s = $Text.Replace('-','+').Replace('_','/')
    while ($s.Length % 4) { $s += '=' }
    $bytes = [Convert]::FromBase64String($s)
    if ((ConvertTo-GF64 $bytes) -cne $Text) { throw 'Noncanonical Base64URL.' }
    return ,$bytes
}
function Get-GFHash([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($script:GFUtf8.GetBytes($Text)))).Replace('-','') }
    finally { $sha.Dispose() }
}
function Assert-GFDevice([string]$Device) {
    if ($Device -cnotmatch '^GF-[A-F0-9]{64}$') { throw 'Device Code must be GF- followed by 64 uppercase hexadecimal characters.' }
}
function Get-GFPublic {
    $point = [Convert]::FromBase64String([IO.File]::ReadAllText($script:GFPublicFile).Trim())
    if ($point.Length -ne 65 -or $point[0] -ne 4) { throw 'Invalid issuer public key.' }
    return ,$point
}
function Get-GFPrivate {
    $blob = [GFCrypto]::Unprotect([IO.File]::ReadAllBytes($script:GFKeyFile))
    if ([Convert]::ToBase64String([GFCrypto]::PublicPoint($blob)) -cne [Convert]::ToBase64String((Get-GFPublic))) {
        [Array]::Clear($blob,0,$blob.Length)
        throw 'Private key does not match the public key for this build.'
    }
    return ,$blob
}
function Initialize-GFKey {
    Open-GFData
    if ([IO.File]::Exists($script:GFKeyFile) -or [IO.File]::Exists($script:GFPublicFile)) {
        throw 'Key already exists. Initialization never replaces an existing key.'
    }
    $blob = [GFCrypto]::NewPrivateKey()
    $public = [Convert]::ToBase64String([GFCrypto]::PublicPoint($blob))
    $stream = [IO.File]::Open($script:GFKeyFile, 'CreateNew', 'Write', 'None')
    try { $protected = [GFCrypto]::Protect($blob); $stream.Write($protected, 0, $protected.Length) }
    finally { $stream.Dispose(); [Array]::Clear($blob, 0, $blob.Length) }
    [IO.File]::WriteAllText($script:GFPublicFile, $public + "`n", $script:GFUtf8)
    if ($PublicHeader) {
        [IO.File]::WriteAllText([IO.Path]::GetFullPath($PublicHeader),
            "#pragma once`n// Public P-256 point only. Keep the matching issuer private key outside Git.`n#define GF_LICENSE_PUBLIC_KEY @`"$public`"`n", $script:GFUtf8)
    }
}
function New-GFChallenge([string]$Device) {
    Assert-GFDevice $Device
    $state = Get-GFState
    $random = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($random) } finally { $rng.Dispose() }
    $nonce = ([BitConverter]::ToString($random)).Replace('-','')
    $now = Get-GFNow; $expires = $now + 300
    $wire = '{"type":"GFC1","v":1,"nonce":"' + $nonce + '","device":"' + $Device + '","issued":' + $now + ',"expires":' + $expires + '}'
    # A device has only one current challenge. Old/replaced challenges fail lookup.
    $state.Challenges = @($state.Challenges | Where-Object { $_.Device -cne $Device -and $_.Expires -gt $now }) + @(
        [pscustomobject]@{ Device=$Device; Wire=$wire; Hash=(Get-GFHash $wire); Expires=$expires; State='ISSUED'; ProofHash=''; License='' })
    Save-GFState $state
    return $wire
}
function Test-GFProof([string]$Wire, [string]$Device) {
    Assert-GFDevice $Device
    if (-not $Wire -or $Wire.Length -gt 4096) { throw 'Invalid proof length.' }
    $p = $Wire | ConvertFrom-Json
    if ($null -eq $p -or $p.type -cne 'GFP1' -or $p.v -cne 1 -or
        $p.device -cne $Device -or $p.challenge_hash -cnotmatch '^[A-F0-9]{64}$') { throw 'Wrong proof type or device.' }
    $point = ConvertFrom-GF64 $p.public_key; $signature = ConvertFrom-GF64 $p.signature
    $unsigned = '{"type":"GFP1","v":1,"challenge_hash":"' + $p.challenge_hash + '","device":"' + $Device + '","public_key":"' + $p.public_key + '"}'
    $canonical = $unsigned.Substring(0,$unsigned.Length-1) + ',"signature":"' + $p.signature + '"}'
    if ($canonical -cne $Wire) { throw 'Noncanonical proof or unexpected fields.' }
    $state = Get-GFState
    $matches = @($state.Challenges | Where-Object { $_.Hash -ceq $p.challenge_hash -and $_.Device -ceq $Device })
    if ($matches.Count -ne 1) { throw 'Challenge not found; generate a fresh challenge.' }
    $challenge = $matches[0]
    if ($challenge.State -cne 'ISSUED') { throw 'Challenge already used.' }
    if ($challenge.Expires -le (Get-GFNow)) { throw 'Challenge expired; generate a fresh challenge.' }
    if ((Get-GFHash $challenge.Wire) -cne $challenge.Hash) { throw 'Stored challenge is damaged.' }
    if (-not [GFCrypto]::Verify($point, $script:GFUtf8.GetBytes("GlassFolders-GFP1-v1`n" + $unsigned), $signature)) {
        throw 'Device proof signature verification failed.'
    }
    $challenge.State = 'VERIFIED'; $challenge.ProofHash = Get-GFHash $Wire
    Save-GFState $state
    return $challenge
}
function Test-GFLicense([string]$Wire, [string]$Device, [string]$Supporter) {
    if (-not $Wire -or $Wire.Length -gt 4096) { throw 'Invalid license length.' }
    $parts = $Wire.Split('.')
    if ($parts.Count -ne 3 -or $parts[0] -cne 'GF1') { throw 'Invalid license format.' }
    $payload = ConvertFrom-GF64 $parts[1]; $signature = ConvertFrom-GF64 $parts[2]
    if (-not [GFCrypto]::Verify((Get-GFPublic), $payload, $signature)) { throw 'License signature verification failed.' }
    $p = $script:GFUtf8.GetString($payload) | ConvertFrom-Json
    if ($p.v -cne 1 -or $p.product -cne 'GlassFolders' -or $p.device -cne $Device -or $p.sid -cne $Supporter -or
        @($p.ent).Count -ne 1 -or $p.ent[0] -cne 'glassfolders' -or @($p.PSObject.Properties).Count -ne 5) {
        throw 'Wrong license product, device or entitlement.'
    }
    return $true
}
function Assert-GFUserInfo([string]$UserName, [string]$ContactNote) {
    if (-not $UserName.Trim() -or $UserName.Trim().Length -gt 80) { throw '请填写用户名称（1–80 个字符）。' }
    if ($ContactNote.Trim().Length -gt 240) { throw '联系方式 / 备注不能超过 240 个字符。' }
}
function Find-GFRecords($Records, [string]$Query) {
    $queryText = $Query.Trim()
    foreach ($record in $Records) {
        $searchText = @($record.Supporter, $record.UserName, $record.ContactNote, $record.Device) -join "`n"
        if (-not $queryText -or $searchText.IndexOf($queryText, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $record }
    }
}
function Set-GFUserInfo([string]$License, [string]$UserName, [string]$ContactNote) {
    Assert-GFUserInfo $UserName $ContactNote
    $state = Get-GFState
    $matches = @($state.Licenses | Where-Object { $_.License -ceq $License })
    if ($matches.Count -ne 1) { throw '找不到唯一的授权记录，请关闭历史窗口后重试。' }
    $matches[0] | Add-Member -NotePropertyName UserName -NotePropertyValue $UserName.Trim() -Force
    $matches[0] | Add-Member -NotePropertyName ContactNote -NotePropertyValue $ContactNote.Trim() -Force
    Save-GFState $state
}
function New-GFLicense([string]$Supporter, [string]$Device, [string]$UserName, [string]$ContactNote) {
    Assert-GFDevice $Device
    if ($Supporter -cnotmatch '^[A-Za-z0-9_-]{1,64}$') { throw 'Supporter ID: use 1-64 letters, digits, underscores or hyphens.' }
    Assert-GFUserInfo $UserName $ContactNote
    $state = Get-GFState
    $verified = @($state.Challenges | Where-Object { $_.Device -ceq $Device -and $_.State -ceq 'VERIFIED' -and $_.Expires -gt (Get-GFNow) })
    if ($verified.Count -ne 1) { throw 'Verify a fresh device proof before issuing a license.' }
    $payload = '{"v":1,"product":"GlassFolders","sid":"' + $Supporter + '","device":"' + $Device + '","ent":["glassfolders"]}'
    $bytes = $script:GFUtf8.GetBytes($payload)
    $private = Get-GFPrivate
    try { $signature = [GFCrypto]::Sign($private, $bytes) }
    finally { [Array]::Clear($private, 0, $private.Length) }
    $wire = 'GF1.' + (ConvertTo-GF64 $bytes) + '.' + (ConvertTo-GF64 $signature)
    [void](Test-GFLicense $wire $Device $Supporter)
    $verified[0].State = 'CONSUMED'; $verified[0].License = $wire
    $state.Licenses = @($state.Licenses) + @([pscustomobject]@{
        Supporter=$Supporter; UserName=$UserName.Trim(); ContactNote=$ContactNote.Trim()
        Device=$Device; Issued=(Get-GFNow); License=$wire; ChallengeHash=$verified[0].Hash })
    # Save the record and consumed state together before returning the code.
    Save-GFState $state
    return $wire
}
if ($InitializeKey) { Initialize-GFKey }
if ($NoUI) { return }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
Open-GFData
if (-not [IO.File]::Exists($script:GFKeyFile)) { throw 'Issuer key is missing. See README before initializing a new product key.' }
$startupKey = Get-GFPrivate
[Array]::Clear($startupKey,0,$startupKey.Length)

function New-GFTable {
    $panel = New-Object Windows.Forms.TableLayoutPanel
    $panel.AutoSize=$true; $panel.AutoSizeMode='GrowAndShrink'
    $panel.ColumnCount=1; $panel.Dock='Top'; $panel.Margin=New-Object Windows.Forms.Padding(0)
    [void]$panel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
    return $panel
}
function Add-GFRow($Panel, $Control) {
    $row=$Panel.RowCount; $Panel.RowCount=$row+1
    [void]$Panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
    $Panel.Controls.Add($Control,0,$row)
}
function New-GFLabel([string]$Text) {
    $label=New-Object Windows.Forms.Label; $label.Text=$Text; $label.AutoSize=$true; $label.Dock='Fill'
    $label.Margin=New-Object Windows.Forms.Padding(0,4,0,6)
    return $label
}
function New-GFText([bool]$Multi=$false) {
    $box=New-Object Windows.Forms.TextBox; $box.Dock='Fill'; $box.Multiline=$Multi
    $box.Margin=New-Object Windows.Forms.Padding(0,3,0,7)
    if ($Multi) { $box.Height=76; $box.ScrollBars='Vertical' }
    return $box
}
function New-GFButton([string]$Text,[scriptblock]$Click) {
    $button=New-Object Windows.Forms.Button; $button.Text=$Text
    $button.AutoSize=$true; $button.AutoSizeMode='GrowAndShrink'
    $button.MinimumSize=New-Object Drawing.Size(160,38)
    $button.Padding=New-Object Windows.Forms.Padding(12,5,12,5)
    $button.Margin=New-Object Windows.Forms.Padding(0,3,12,3)
    $button.FlatStyle='Flat'; $button.BackColor=[Drawing.Color]::White
    $button.Add_Click($Click); return $button
}
function New-GFFlow {
    $flow=New-Object Windows.Forms.FlowLayoutPanel; $flow.Dock='Fill'; $flow.AutoSize=$true
    $flow.AutoSizeMode='GrowAndShrink'; $flow.WrapContents=$true
    $flow.Margin=New-Object Windows.Forms.Padding(0)
    return $flow
}
function Add-GFField($Panel,[string]$Text,$Box) {
    $row=$Panel.RowCount; $Panel.RowCount=$row+1
    [void]$Panel.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
    $label=New-GFLabel $Text; $label.Anchor='Left'; $label.Dock='None'
    $label.Margin=New-Object Windows.Forms.Padding(0,3,12,7)
    $Panel.Controls.Add($label,0,$row); $Panel.Controls.Add($Box,1,$row)
}
function Set-GFWindowSize($Window,[int]$Width,[int]$Height) {
    $area=[Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $Window.ClientSize=New-Object Drawing.Size([Math]::Min($Width,$area.Width-60),[Math]::Min($Height,$area.Height-80))
    $Window.MinimumSize=New-Object Drawing.Size([Math]::Min(720,$area.Width-20),[Math]::Min(580,$area.Height-20))
}
function Save-GFPreview($Window,[string]$Path) {
    $Window.ShowInTaskbar=$false; $Window.Opacity=0
    $Window.Show(); [Windows.Forms.Application]::DoEvents()
    if ($PreviewScale -ne 1) {
        $Window.SuspendLayout()
        $Window.AutoScaleMode='None'
        $Window.Font=New-Object Drawing.Font($Window.Font.FontFamily,([single]($Window.Font.Size * $PreviewScale)))
        $Window.Scale((New-Object Drawing.SizeF($PreviewScale,$PreviewScale)))
        # Keep the window inside the working area, as with a smaller display at high scaling.
        $Window.MinimumSize=New-Object Drawing.Size(0,0)
        Set-GFWindowSize $Window 850 760
        $Window.ResumeLayout($true)
        [Windows.Forms.Application]::DoEvents()
    }
    $Window.PerformLayout()
    $preview=New-Object Drawing.Bitmap($Window.Width,$Window.Height)
    try {
        $Window.DrawToBitmap($preview,(New-Object Drawing.Rectangle(0,0,$Window.Width,$Window.Height)))
        $preview.Save([IO.Path]::GetFullPath($Path),[Drawing.Imaging.ImageFormat]::Png)
    } finally { $preview.Dispose() }
}
function Assert-GFVisibleBounds($Control) {
    # Check actual WinForms layout after font/DPI scaling, not hard-coded coordinates.
    foreach ($child in $Control.Controls) {
        if ($Control -is [Windows.Forms.TableLayoutPanel] -or $Control -is [Windows.Forms.FlowLayoutPanel]) {
            if ($child.Right -gt $Control.ClientSize.Width -or $child.Bottom -gt $Control.ClientSize.Height) {
                throw ('布局超出容器：' + $child.Text)
            }
        }
        Assert-GFVisibleBounds $child
    }
}
function Show-GFFailure($Exception) {
    $status.Text='操作失败：' + $Exception.Message
    [void][Windows.Forms.MessageBox]::Show($Exception.Message,'GlassFolders','OK','Warning')
}
function Show-GFHistory([string]$PreviewFile) {
    $history=New-Object Windows.Forms.Form
    $history.Text='GlassFolders · 授权历史与用户资料'
    $history.Font=New-Object Drawing.Font('Microsoft YaHei UI',10); $history.StartPosition='CenterParent'
    $history.AutoScaleMode='Dpi'; $history.AutoScaleDimensions=New-Object Drawing.SizeF(96,96)
    Set-GFWindowSize $history 1080 720
    $root=New-GFTable; $root.AutoSize=$false; $root.Dock='Fill'
    $root.Padding=New-Object Windows.Forms.Padding(16)
    $search=New-GFText
    $searchRow=New-GFTable; $searchRow.ColumnCount=2
    $searchRow.ColumnStyles.Clear()
    [void]$searchRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
    [void]$searchRow.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
    Add-GFField $searchRow '搜索用户 / 编号 / 设备' $search
    Add-GFRow $root $searchRow

    $grid=New-Object Windows.Forms.DataGridView; $grid.Dock='Fill'; $grid.ReadOnly=$true
    $grid.AllowUserToAddRows=$false; $grid.AllowUserToDeleteRows=$false
    $grid.AllowUserToResizeRows=$false; $grid.RowHeadersVisible=$false
    $grid.SelectionMode='FullRowSelect'; $grid.MultiSelect=$false
    $grid.AutoSizeColumnsMode='None'; $grid.BackgroundColor=[Drawing.Color]::White
    $grid.AutoSizeRowsMode='AllCells'; $grid.ClipboardCopyMode='EnableAlwaysIncludeHeaderText'
    $grid.ColumnHeadersHeightSizeMode='AutoSize'
    $grid.Margin=New-Object Windows.Forms.Padding(0,4,0,8)
    Add-GFRow $root $grid
    $root.RowStyles[1].SizeType='Percent'; $root.RowStyles[1].Height=100
    $table=New-Object Data.DataTable
    foreach ($column in @('Supporter','UserName','ContactNote','Device','Issued','License')) { [void]$table.Columns.Add($column) }
    $grid.AutoGenerateColumns=$false
    $columns=@(
        @('Supporter','授权编号',100), @('UserName','用户名称',130), @('ContactNote','联系方式 / 备注',210),
        @('Device','设备码',230), @('Issued','签发时间（本地）',165)
    )
    foreach ($column in $columns) {
        $gridColumn=New-Object Windows.Forms.DataGridViewTextBoxColumn
        $gridColumn.Name=$column[0]; $gridColumn.DataPropertyName=$column[0]
        $gridColumn.HeaderText=$column[1]; $gridColumn.Width=$column[2]; $gridColumn.MinimumWidth=70
        [void]$grid.Columns.Add($gridColumn)
    }
    $licenseColumn=New-Object Windows.Forms.DataGridViewTextBoxColumn
    $licenseColumn.Name='License'; $licenseColumn.DataPropertyName='License'; $licenseColumn.Visible=$false
    [void]$grid.Columns.Add($licenseColumn)
    $grid.DataSource=$table
    $historySummary=New-GFLabel ''
    Add-GFRow $root $historySummary
    $details=New-GFTable; $details.ColumnCount=2
    $details.ColumnStyles.Clear()
    [void]$details.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
    [void]$details.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
    $historyName=New-GFText; $historyName.MaxLength=80
    $historyNote=New-GFText; $historyNote.MaxLength=240
    $historyDevice=New-GFText; $historyDevice.ReadOnly=$true
    $historyLicense=New-GFText $true; $historyLicense.ReadOnly=$true; $historyLicense.Height=64
    Add-GFField $details '用户名称 *' $historyName
    Add-GFField $details '联系方式 / 备注' $historyNote
    Add-GFField $details '完整设备码' $historyDevice
    Add-GFField $details '完整授权码' $historyLicense
    Add-GFRow $root $details
    $actions=New-GFFlow
    $copyHistory=New-GFButton '复制所选授权' {
        try { if ($historyLicense.Text) { [Windows.Forms.Clipboard]::SetText($historyLicense.Text) } }
        catch { Show-GFFailure $_.Exception }
    }
    $copyHistory.Enabled=$false
    $saveUser=New-GFButton '保存用户资料' {
        try {
            if (-not $historyLicense.Text) { throw '请先选择一条授权记录。' }
            $selectedLicense=$historyLicense.Text
            Set-GFUserInfo $selectedLicense $historyName.Text $historyNote.Text
            & $reloadHistory
            foreach ($row in $grid.Rows) {
                if ([string]$row.Cells['License'].Value -ceq $selectedLicense) {
                    $grid.CurrentCell=$row.Cells['UserName']; break
                }
            }
            $historySummary.Text='用户资料已保存。授权码保持有效，无需重新激活。'
        } catch { Show-GFFailure $_.Exception }
    }
    $saveUser.Enabled=$false
    $actions.Controls.Add($copyHistory); $actions.Controls.Add($saveUser)
    Add-GFRow $root $actions
    $privacy=New-GFLabel '用户资料仅保存在本机，可为旧记录补填；不会写入发给手机的授权码。'
    Add-GFRow $root $privacy
    $history.Controls.Add($root)
    $grid.Add_SelectionChanged({
        $selected=$grid.CurrentRow
        if ($null -eq $selected) {
            $historyName.Clear(); $historyNote.Clear(); $historyDevice.Clear(); $historyLicense.Clear()
            $saveUser.Enabled=$false; $copyHistory.Enabled=$false
        } else {
            $historyName.Text=[string]$selected.Cells['UserName'].Value
            $historyNote.Text=[string]$selected.Cells['ContactNote'].Value
            $historyDevice.Text=[string]$selected.Cells['Device'].Value
            $historyLicense.Text=[string]$selected.Cells['License'].Value
            $saveUser.Enabled=$true; $copyHistory.Enabled=$true
        }
    })
    $reloadHistory = {
        $all=@((Get-GFState).Licenses)
        $matches=@(Find-GFRecords $all $search.Text)
        $table.Rows.Clear()
        foreach ($record in ($matches | Sort-Object Issued -Descending)) {
            $date=([DateTime]'1970-01-01Z').ToUniversalTime().AddSeconds([double]$record.Issued).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
            [void]$table.Rows.Add([string]$record.Supporter,[string]$record.UserName,[string]$record.ContactNote,
                [string]$record.Device,$date,[string]$record.License)
        }
        $historySummary.Text='显示 ' + $matches.Count + ' / ' + $all.Count + ' 条。选中记录可查看完整内容、复制授权或补填用户资料。'
    }
    $search.Add_TextChanged({ try { & $reloadHistory } catch { Show-GFFailure $_.Exception } })
    try {
        & $reloadHistory
        if ($PreviewFile) {
            Save-GFPreview $history $PreviewFile
            Assert-GFVisibleBounds $root
            $allRecords=@((Get-GFState).Licenses)
            if ($grid.Rows.Count -ne $allRecords.Count) { throw 'History UI did not load all records.' }
            if ($grid.Rows.Count) {
                $grid.CurrentCell=$grid.Rows[0].Cells['UserName']
                [Windows.Forms.Application]::DoEvents()
                if ($historyLicense.Text -cne [string]$grid.CurrentRow.Cells['License'].Value -or -not $copyHistory.Enabled) {
                    throw 'History selection did not load the full license.'
                }
                $query=[string]$grid.CurrentRow.Cells['Supporter'].Value
                $search.Text=$query; [Windows.Forms.Application]::DoEvents()
                if ($grid.Rows.Count -ne @(Find-GFRecords $allRecords $query).Count) { throw 'History search did not refresh rows.' }
            }
            $search.Text=[Guid]::NewGuid().ToString('N'); [Windows.Forms.Application]::DoEvents()
            if ($grid.Rows.Count -ne 0 -or $historyLicense.Text -or $copyHistory.Enabled -or $saveUser.Enabled) {
                throw 'Empty history search kept a stale selection.'
            }
            $search.Clear(); [Windows.Forms.Application]::DoEvents()
            if ($grid.Rows.Count -ne $allRecords.Count) { throw 'Clearing history search did not restore records.' }
        } else { [void]$history.ShowDialog($form) }
    } finally { $history.Dispose(); $table.Dispose() }
}

$form=New-Object Windows.Forms.Form
$form.Text='GlassFolders 离线授权签发器 1.1.1'
$form.StartPosition='CenterScreen'; $form.Font=New-Object Drawing.Font('Microsoft YaHei UI',10)
$form.AutoScaleMode='Dpi'; $form.AutoScaleDimensions=New-Object Drawing.SizeF(96,96)
$form.BackColor=[Drawing.Color]::FromArgb(244,246,250)
Set-GFWindowSize $form 850 790
$outer=New-GFTable; $outer.AutoSize=$false; $outer.Dock='Fill'
$outer.Padding=New-Object Windows.Forms.Padding(22,14,22,14)
$heading=New-GFLabel 'GlassFolders · 本地离线签发'
Add-GFRow $outer $heading
Add-GFRow $outer (New-GFLabel '填写用户资料 → 设备绑定 → 验证回执 → 签发授权')

$scroll=New-Object Windows.Forms.Panel; $scroll.Dock='Fill'; $scroll.AutoScroll=$true
$scroll.Margin=New-Object Windows.Forms.Padding(0,6,0,8)
$content=New-GFTable
$content.Padding=New-Object Windows.Forms.Padding(0,0,20,0)
$fields=New-GFTable; $fields.ColumnCount=2; $fields.ColumnStyles.Clear()
[void]$fields.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('AutoSize')))
[void]$fields.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent',100)))
$idBox=New-GFText; $idBox.Text='0001'; $idBox.MaxLength=64
$userBox=New-GFText; $userBox.MaxLength=80
$noteBox=New-GFText; $noteBox.MaxLength=240
$deviceBox=New-GFText
Add-GFField $fields '授权编号' $idBox
Add-GFField $fields '用户名称 *' $userBox
Add-GFField $fields '联系方式 / 备注' $noteBox
Add-GFField $fields '设备码（GF-）' $deviceBox
Add-GFRow $content $fields
Add-GFRow $content (New-GFLabel '* 用户名称必填；联系方式 / 备注选填，仅保存在电脑的授权历史中。')
$challengeActions=New-GFFlow
$challengeActions.Controls.Add((New-GFButton '1. 生成绑定码并复制' {
    try {
        Assert-GFUserInfo $userBox.Text $noteBox.Text
        $wire=New-GFChallenge $deviceBox.Text.Trim(); $challengeBox.Text=$wire
        [Windows.Forms.Clipboard]::SetText($wire)
        $script:GFActiveExpires=($wire | ConvertFrom-Json).expires
        $status.Text='已复制绑定码：让用户在手机设置中点击“绑定本机”，再发回设备回执。'
        $licenseBox.Clear(); $proofBox.Clear()
    } catch { Show-GFFailure $_.Exception }
}))
Add-GFRow $content $challengeActions
$challengeBox=New-GFText $true; $challengeBox.ReadOnly=$true
Add-GFRow $content $challengeBox
Add-GFRow $content (New-GFLabel '设备回执（GFP1）')
$proofBox=New-GFText $true
Add-GFRow $content $proofBox
$issueActions=New-GFFlow
$issueActions.Controls.Add((New-GFButton '2. 粘贴回执并验证' {
    try {
        $proofBox.Text=[Windows.Forms.Clipboard]::GetText().Trim()
        [void](Test-GFProof $proofBox.Text $deviceBox.Text.Trim())
        $status.Text='回执签名验证通过；请在绑定码到期前签发授权。'
    } catch { Show-GFFailure $_.Exception }
}))
$issueActions.Controls.Add((New-GFButton '3. 签发授权并复制' {
    try {
        $licenseBox.Text=New-GFLicense $idBox.Text.Trim() $deviceBox.Text.Trim() $userBox.Text $noteBox.Text
        [Windows.Forms.Clipboard]::SetText($licenseBox.Text)
        $status.Text='签发成功，用户资料与授权已保存。让用户粘贴激活，再点“应用并注销”。'
    } catch { Show-GFFailure $_.Exception }
}))
$issueActions.Controls.Add((New-GFButton '重新复制授权' {
    try { if ($licenseBox.Text) { [Windows.Forms.Clipboard]::SetText($licenseBox.Text) } }
    catch { Show-GFFailure $_.Exception }
}))
Add-GFRow $content $issueActions
$licenseBox=New-GFText $true; $licenseBox.ReadOnly=$true
Add-GFRow $content $licenseBox
$scroll.Controls.Add($content)
Add-GFRow $outer $scroll
$outer.RowStyles[2].SizeType='Percent'; $outer.RowStyles[2].Height=100

$footer=New-GFTable
$footerActions=New-GFFlow
$footerActions.Controls.Add((New-GFButton '查看历史授权 / 用户资料' {
    try { Show-GFHistory } catch { Show-GFFailure $_.Exception }
}))
$timerLabel=New-GFLabel '绑定码有效期：5 分钟'
$timerLabel.Dock='None'; $timerLabel.Anchor='Left'
$timerLabel.Margin=New-Object Windows.Forms.Padding(0,10,0,5)
$footerActions.Controls.Add($timerLabel)
Add-GFRow $footer $footerActions
$status=New-GFLabel '等待用户资料和设备码。授权永久有效，仅用于对应硬件。'
Add-GFRow $footer $status
Add-GFRow $outer $footer
$form.Controls.Add($outer)
$script:GFActiveExpires=0
$timer=New-Object Windows.Forms.Timer; $timer.Interval=1000
$timer.Add_Tick({
    if ($script:GFActiveExpires) {
        $remaining=[Math]::Max(0,$script:GFActiveExpires-(Get-GFNow))
        $timerLabel.Text='绑定码剩余：' + [TimeSpan]::FromSeconds($remaining).ToString('mm\:ss')
    }
})
$timer.Start()
try {
    if ($UISmokeTest) {
        if ($PreviewScale -lt 1 -or $PreviewScale -gt 2) { throw 'PreviewScale must be between 1 and 2.' }
        # Exercise layout even when no screenshot was requested.
        $form.ShowInTaskbar=$false; $form.Opacity=0
        $form.Show(); [Windows.Forms.Application]::DoEvents()
        if ($PreviewPath) { Save-GFPreview $form $PreviewPath }
        Assert-GFVisibleBounds $outer
        if ($HistoryPreviewPath) { Show-GFHistory $HistoryPreviewPath }
        Write-Output 'Issuer UI layout checked; matching private/public key loaded successfully.'
    } else { [void]$form.ShowDialog() }
} finally {
    $timer.Stop(); $timer.Dispose(); $form.Dispose()
    if ($script:GFDataLock) { $script:GFDataLock.Dispose(); $script:GFDataLock=$null }
}
