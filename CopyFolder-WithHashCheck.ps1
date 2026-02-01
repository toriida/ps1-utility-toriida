# --- コマンドライン引数 ---
param(
    [Parameter(Mandatory=$true)][string]$SrcParent,  # 移行元親フォルダの絶対パス
    [Parameter(Mandatory=$true)][string]$DstParent   # 移行先親フォルダの絶対パス
)

# --- 設定項目 ---
$EXCLUDE_FILES = @("Thumbs.db", "desktop.ini")

# --- フォルダ名の入力 ---
$Subj = Read-Host -Prompt "コピーするフォルダ名を入力してください"
if (-not $Subj) { Write-Error "フォルダ名が空です"; exit 1 }

# --- パスの計算 ---
$LogDir = Join-Path $([System.IO.Path]::GetTempPath()) "CopyFolder-WithHashCheck\Log"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir }
$SrcLog  = Join-Path $LogDir "${Subj}-Src.txt"
$DstLog  = Join-Path $LogDir "${Subj}-Dst.txt"

$SrcPath = Join-Path $SrcParent $Subj
$DstPath = Join-Path $DstParent $Subj
if (-not (Test-Path $SrcPath)) { Write-Error "移行元フォルダが見つかりません: $SrcPath"; exit 1 }
if (-not (Test-Path $DstParent)) { Write-Error "移行先親フォルダが見つかりません: $DstParent"; exit 1 }
if (Test-Path $DstPath) { Write-Error "移行先フォルダが存在します: $DstPath"; exit 1 }

# --- 関数: ハッシュリスト作成 ---
function Log-NameAndHash {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [Parameter(Mandatory=$true)][string]$OutFile
    )
    Get-ChildItem -Path $RootPath -Recurse -File | Where-Object {
        $_.Name -notin $EXCLUDE_FILES
    } | ForEach-Object {
        $RelativePath = $_.Name
        $Hash         = (Get-FileHash -Path $_.FullName -Algorithm MD5).Hash
        "$RelativePath`t$Hash"
    } | Sort-Object | Out-File -FilePath $OutFile -Encoding UTF8
}

# --- Dotfiles置換 ---
Get-ChildItem -Path $SrcPath -Recurse -File -Force | Where-Object { $_.Name.StartsWith(".") } | ForEach-Object {
    $NewName = "_" + $_.Name.Substring(1)
    Rename-Item -Path $_.FullName -NewName $NewName
}

# --- 移行元のハッシュ出力 ---
Log-NameAndHash -RootPath $SrcPath -OutFile $SrcLog

# --- コピー実行 ----
# /E...サブフォルダ含む /XF...除外 /R...リトライ /W...再試行待ち(秒)
robocopy "$SrcPath" "$DstPath" /E /COPY:DT /XF $EXCLUDE_FILES /R:1 /W:1
Write-Host "コピー終了"

# --- 移行先のハッシュ出力 ---
Log-NameAndHash -RootPath $DstPath -OutFile $DstLog

# --- 検証 ---
$Diff = Compare-Object (Get-Content $SrcLog) (Get-Content $DstLog)

if ($null -eq $Diff) {
    Write-Host "〇内容一致"
    exit 0
} else {
    Write-Error "×内容不一致"
    $Diff | ForEach-Object {
        Write-Error "$($_.SideIndicator)`t$($_.InputObject)"
    }
    exit 1
}

