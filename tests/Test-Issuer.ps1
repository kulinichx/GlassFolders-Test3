$ErrorActionPreference = 'Stop'
$testRoot = Join-Path $PSScriptRoot ('.tmp\' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$publicFile = Join-Path $testRoot 'public.txt'
$header = Join-Path $testRoot 'key.h'
. (Join-Path $PSScriptRoot '..\tools\issuer\GlassFoldersIssuer.ps1') -NoUI -InitializeKey `
    -DataDirectory (Join-Path $testRoot 'private') -PublicKeyFile $publicFile -PublicHeader $header
$script:Passed = 0
function Assert-GF([bool]$Value, [string]$Name) {
    if (-not $Value) { throw "FAIL: $Name" }
    $script:Passed++; Write-Output "PASS: $Name"
}
function Reject-GF([scriptblock]$Action, [string]$Name) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-GF $rejected $Name
}
function New-TestProof([string]$Challenge, [string]$Device) {
    $key = [GFCrypto]::NewPrivateKey()
    try {
        $point = ConvertTo-GF64 ([GFCrypto]::PublicPoint($key))
        $unsigned = '{"type":"GFP1","v":1,"challenge_hash":"' + (Get-GFHash $Challenge) + '","device":"' + $Device + '","public_key":"' + $point + '"}'
        $signature = [GFCrypto]::Sign($key, $script:GFUtf8.GetBytes("GlassFolders-GFP1-v1`n" + $unsigned))
        return $unsigned.Substring(0,$unsigned.Length-1) + ',"signature":"' + (ConvertTo-GF64 $signature) + '"}'
    } finally { [Array]::Clear($key,0,$key.Length) }
}
try {
    $device = 'GF-' + ('A' * 64); $other = 'GF-' + ('B' * 64)
    Reject-GF { Initialize-GFKey } 'Existing key is never overwritten'
    Reject-GF { New-GFChallenge 'bad' } 'Malformed device code rejected'
    Reject-GF { New-GFLicense '0001' $device 'Test user' '' } 'License requires verified challenge'
    $challenge = New-GFChallenge $device
    $proof = New-TestProof $challenge $device
    Reject-GF { Test-GFProof ($proof.Replace('GFP1','RHP1')) $device } 'RC7 proof rejected'
    Reject-GF { Test-GFProof ($proof + ' ') $device } 'Noncanonical proof rejected'
    Reject-GF { Test-GFProof $proof $other } 'Wrong device rejected'
    $obj = $proof | ConvertFrom-Json
    [byte[]]$sig = ConvertFrom-GF64 $obj.signature; $sig[$sig.Length-1] = $sig[$sig.Length-1] -bxor 1
    Reject-GF { Test-GFProof ($proof.Replace($obj.signature,(ConvertTo-GF64 $sig))) $device } 'Tampered proof signature rejected'
    Assert-GF ((Get-GFState).Challenges[0].State -ceq 'ISSUED') 'Invalid proofs do not consume challenge'
    [void](Test-GFProof $proof $device)
    Reject-GF { Test-GFProof $proof $device } 'Verified proof cannot be replayed'
    Reject-GF { New-GFLicense '0001' $device '   ' '' } 'Missing user name rejected'
    Reject-GF { New-GFLicense '0001' $device ('x' * 81) '' } 'Oversized user name rejected'
    Reject-GF { New-GFLicense '0001' $device 'Test user' ('x' * 241) } 'Oversized contact note rejected'
    Assert-GF ((Get-GFState).Challenges[0].State -ceq 'VERIFIED') 'Invalid user info preserves verified challenge'
    Reject-GF { New-GFLicense 'injected"id' $device } 'Invalid supporter ID rejected'
    $blockedFile = [IO.File]::Open($script:GFStateFile,'Open','Read','None')
    try { Reject-GF { New-GFLicense '0001' $device 'Test user' '' } 'Record access failure does not return a license' }
    finally { $blockedFile.Dispose() }
    Assert-GF ((Get-GFState).Challenges[0].State -ceq 'VERIFIED') 'Failed record operation preserves verified challenge'
    $originalPublic = [IO.File]::ReadAllText($script:GFPublicFile)
    $wrongKey = [GFCrypto]::NewPrivateKey()
    try {
        [IO.File]::WriteAllText($script:GFPublicFile,[Convert]::ToBase64String([GFCrypto]::PublicPoint($wrongKey)))
        Reject-GF { Get-GFPrivate } 'Mismatched issuer key rejected'
    } finally {
        [Array]::Clear($wrongKey,0,$wrongKey.Length)
        [IO.File]::WriteAllText($script:GFPublicFile,$originalPublic)
    }
    $userName = [string][char]0x5C0F + [char]0x660E
    $userNote = ' QQ: 123456; order [A]%_''" '
    $license = New-GFLicense '0001' $device (' ' + $userName + ' ') $userNote
    Assert-GF (Test-GFLicense $license $device '0001') 'Issue and verify license'
    Reject-GF { New-GFLicense '0001' $device 'Test user' '' } 'Consumed challenge cannot issue twice'
    Reject-GF { Test-GFLicense $license $other '0001' } 'License for another device rejected'
    Reject-GF { Test-GFLicense ($license.Replace('GF1.','RH1.')) $device '0001' } 'RC7 license format rejected'
    $parts = $license.Split('.')
    $tampered = $script:GFUtf8.GetString((ConvertFrom-GF64 $parts[1])).Replace('0001','0002')
    Reject-GF { Test-GFLicense ('GF1.'+(ConvertTo-GF64 $script:GFUtf8.GetBytes($tampered))+'.'+$parts[2]) $device '0002' } 'Tampered license payload rejected'
    $stored = Get-GFState
    Assert-GF ($stored.Challenges[0].State -ceq 'CONSUMED' -and $stored.Licenses[0].License -ceq $license) 'License and consumed state saved together'
    Assert-GF ($stored.Licenses[0].UserName -ceq $userName -and $stored.Licenses[0].ContactNote -ceq $userNote.Trim()) 'Unicode user info saved and trimmed'
    $payloadObject = $script:GFUtf8.GetString((ConvertFrom-GF64 $license.Split('.')[1])) | ConvertFrom-Json
    Assert-GF (@($payloadObject.PSObject.Properties).Count -eq 5 -and -not $payloadObject.UserName -and -not $payloadObject.ContactNote) 'User info stays out of shared license payload'
    Assert-GF (@(Find-GFRecords $stored.Licenses $userName).Count -eq 1) 'History searches Unicode user name'
    Assert-GF (@(Find-GFRecords $stored.Licenses '[A]%_''"').Count -eq 1) 'History treats search punctuation literally'
    Assert-GF (@(Find-GFRecords $stored.Licenses 'qq:').Count -eq 1) 'History searches contact info without case sensitivity'
    Assert-GF (@(Find-GFRecords $stored.Licenses '0001').Count -eq 1 -and @(Find-GFRecords $stored.Licenses $device).Count -eq 1) 'History searches ID and full device code'
    Assert-GF (@(Find-GFRecords $stored.Licenses 'missing-user').Count -eq 0) 'History returns empty for unmatched query'
    # Simulate a real record from v1.0 without metadata, then supplement it.
    $stored.Licenses[0].PSObject.Properties.Remove('UserName')
    $stored.Licenses[0].PSObject.Properties.Remove('ContactNote')
    Save-GFState $stored
    Assert-GF (@(Find-GFRecords (Get-GFState).Licenses '0001').Count -eq 1) 'Legacy records remain readable and searchable'
    Set-GFUserInfo $license $userName $userNote
    $updated=(Get-GFState).Licenses[0]
    Assert-GF ($updated.UserName -ceq $userName -and $updated.ContactNote -ceq $userNote.Trim()) 'Legacy user info can be supplemented'
    Assert-GF ($updated.License -ceq $license -and (Test-GFLicense $updated.License $device '0001')) 'Editing user info preserves original valid license'
    Reject-GF { Set-GFUserInfo 'missing-license' 'Test user' '' } 'User edit requires an existing unique record'
    Reject-GF { Set-GFUserInfo $license '' '' } 'User edit rejects an empty name'
    # Node's OpenSSL backend is independent of the CNG implementation.
    $node = $env:GF_TEST_NODE
    if (-not $node) { $node = (Get-Command node -ErrorAction SilentlyContinue).Source }
    if (-not $node) { throw 'Set GF_TEST_NODE to node.exe for independent signature verification.' }
    [byte[]]$prefix = 0x30,0x59,0x30,0x13,0x06,0x07,0x2A,0x86,0x48,0xCE,0x3D,0x02,0x01,0x06,0x08,0x2A,0x86,0x48,0xCE,0x3D,0x03,0x01,0x07,0x03,0x42,0x00
    [byte[]]$spki = $prefix + (Get-GFPublic)
    $pem = "-----BEGIN PUBLIC KEY-----`n" + [Convert]::ToBase64String($spki) + "`n-----END PUBLIC KEY-----`n"
    $pubPath = Join-Path $testRoot 'public.pem'; $payloadPath = Join-Path $testRoot 'payload.bin'; $sigPath = Join-Path $testRoot 'signature.bin'
    [IO.File]::WriteAllText($pubPath,$pem)
    [IO.File]::WriteAllBytes($payloadPath,(ConvertFrom-GF64 $parts[1]))
    [IO.File]::WriteAllBytes($sigPath,(ConvertFrom-GF64 $parts[2]))
    [IO.File]::WriteAllText((Join-Path $testRoot 'proof.json'),$proof,$script:GFUtf8)
    & $node (Join-Path $PSScriptRoot 'crypto-interop.cjs') $testRoot
    Assert-GF ($LASTEXITCODE -eq 0) 'Node/OpenSSL independently verifies license and device proof'
    $der = [IO.File]::ReadAllBytes((Join-Path $testRoot 'node-public.der'))
    [byte[]]$point = $der[($der.Length-65)..($der.Length-1)]
    Assert-GF ([GFCrypto]::Verify($point,[IO.File]::ReadAllBytes($payloadPath),[IO.File]::ReadAllBytes((Join-Path $testRoot 'node-signature.bin')))) 'CNG verifies independent Node/OpenSSL signature'
    $oldChallenge = New-GFChallenge $other; $oldProof = New-TestProof $oldChallenge $other
    [void](New-GFChallenge $other)
    Reject-GF { Test-GFProof $oldProof $other } 'Replaced challenge rejected'
    $fresh = New-GFChallenge $other; $freshProof = New-TestProof $fresh $other
    $state = Get-GFState
    ($state.Challenges | Where-Object Device -CEQ $other).Expires = (Get-GFNow)-1
    Save-GFState $state
    Reject-GF { Test-GFProof $freshProof $other } 'Expired proof rejected'
    $fresh = New-GFChallenge $other; $freshProof = New-TestProof $fresh $other
    [void](Test-GFProof $freshProof $other)
    $state = Get-GFState
    ($state.Challenges | Where-Object Device -CEQ $other).Expires = (Get-GFNow)-1
    Save-GFState $state
    Reject-GF { New-GFLicense '0002' $other 'Other user' '' } 'Expiry checked again at issuance'
    Reject-GF { [GFCrypto]::FromDER([byte[]](48,6,2,1,128,2,1,1)) } 'Negative DER integer rejected'
    Reject-GF { [GFCrypto]::FromDER([byte[]](48,7,2,2,0,1,2,1,1)) } 'Nonminimal DER integer rejected'
    $script:GFDataLock.Dispose(); $script:GFDataLock=$null
    Assert-GF ((Get-GFState).Licenses[0].License -ceq $license) 'Records survive close and reopen'
    Assert-GF ((Get-GFState).Licenses[0].UserName -ceq $userName) 'User info survives close and reopen'
    Reject-GF { [IO.File]::Open((Join-Path $script:GFData 'issuer.lock'),'OpenOrCreate','ReadWrite','None') } 'Concurrent writer rejected'
    # Run real WinForms binding/search/selection with isolated test records and key.
    $script:GFDataLock.Dispose(); $script:GFDataLock=$null
    foreach ($scale in @(1, 1.5)) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $PSScriptRoot '..\tools\issuer\GlassFoldersIssuer.ps1') `
            -UISmokeTest -PreviewScale $scale -DataDirectory (Join-Path $testRoot 'private') -PublicKeyFile $publicFile `
            -PreviewPath (Join-Path $testRoot 'main.png') -HistoryPreviewPath (Join-Path $testRoot 'history.png')
        Assert-GF ($LASTEXITCODE -eq 0) ("WinForms layout and history interactions at scale " + $scale)
    }
    [void](Get-GFState)
    [IO.File]::WriteAllText($script:GFStateFile,'broken json')
    Reject-GF { New-GFChallenge $device } 'Damaged records are not silently reset'
    Write-Output "All $script:Passed issuer checks passed."
} finally {
    if ($script:GFDataLock) { $script:GFDataLock.Dispose(); $script:GFDataLock=$null }
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $allowed = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp')) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid test cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
