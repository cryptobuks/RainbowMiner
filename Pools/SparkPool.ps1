﻿using module ..\Include.psm1

param(
    [PSCustomObject]$Wallets,
    [PSCustomObject]$Params,
    [alias("WorkerName")]
    [String]$Worker,
    [TimeSpan]$StatSpan,
    [String]$DataWindow = "estimate_current",
    [Bool]$InfoOnly = $false,
    [Bool]$AllowZero = $false,
    [String]$StatAverage = "Minute_10"
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$Pool_Region_Default = "asia"

[hashtable]$Pool_RegionsTable = @{}
@("eu","us","asia","cn") | Foreach-Object {$Pool_RegionsTable.$_ = Get-Region $_}

$Pool_Request = [PSCustomObject]@{}

try {
    $Pool_Request = Invoke-RestMethodAsync "https://www.sparkpool.com/v1/pool/stats?pool=SPARK_POOL_CN" -tag $Name -retry 5 -retrywait 250 -cycletime 120
    if ($Pool_Request.code -ne 200) {throw}
}
catch {
    if ($Error.Count){$Error.RemoveAt(0)}
    Write-Log -Level Warn "Pool API ($Name) has failed. "
    return
}

$Pools_Data = @(
    [PSCustomObject]@{id = "beam";    coin = "Beam";            algo = "Equihash25x5"; symbol = "BEAM";    port = 2222;  fee = 1; region = @("asia","eu","us")}
    [PSCustomObject]@{id = "";        coin = "Ethereum";        algo = "Ethash";       symbol = "ETH";     port = 3333;  fee = 1; region = @("cn")}
    [PSCustomObject]@{id = "etc";     coin = "EthereumClassic"; algo = "Ethash";       symbol = "ETC";     port = 5555;  fee = 1; region = @("cn")}
    [PSCustomObject]@{id = "grin";    coin = "Grin";            algo = "Cuckaroo29";   symbol = "GRIN_29"; port = 6666;  fee = 1; region = @("asia","eu","us")}
    [PSCustomObject]@{id = "grin";    coin = "Grin";            algo = "Cuckatoo31";   symbol = "GRIN_31"; port = 6667;  fee = 1; region = @("asia","eu","us")}
    [PSCustomObject]@{id = "xmr";     coin = "Monero";          algo = "Monero";       symbol = "XMR";     port = 11000; fee = 1; region = @("cn")}    
)

$Pools_Data | Where-Object {$Wallets."$($_.symbol -replace "_.+$")" -or $InfoOnly} | ForEach-Object {
    $Pool_Port = $_.port
    $Pool_Algorithm = $_.algo
    $Pool_Algorithm_Norm = Get-Algorithm $_.algo
    $Pool_Currency = $_.symbol
    $Pool_Coin = $_.coin
    $Pool_Fee = $_.fee
    $Pool_ID = $_.id
    $Pool_Regions = $_.region

    $Pool_Request.data | Where-Object currency -eq $Pool_Currency | Foreach-Object {
        if (-not $InfoOnly) {
            $NewStat = -not (Test-Path ".\Stats\Pools\$($Name)_$($Pool_Currency)_Profit.txt")
            $Stat = Set-Stat -Name "$($Name)_$($Pool_Currency)_Profit" -Value ($_."$(if ($NewStat) {"meanIncome24h"} else {"income"})" / $_.incomeHashrate) -Duration $(if ($NewStat) {New-TimeSpan -Days 1} else {$StatSpan}) -ChangeDetection $false -HashRate $_.hashrate -BlockRate $_.blocks -Quiet
        }

        foreach ($Pool_Region in $Pool_Regions) {
            [PSCustomObject]@{
                Algorithm     = $Pool_Algorithm_Norm
                CoinName      = $Pool_Coin
                CoinSymbol    = $Pool_Currency -replace '_.+$'
                Currency      = $Pool_Currency -replace '_.+$'
                Price         = $Stat.$StatAverage #instead of .Live
                StablePrice   = $Stat.Week
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = "$(if ($Pool_ID) {"$($Pool_ID)-"})$($Pool_Region).sparkpool.com"
                Port          = $Pool_Port
                User          = "$($Wallets."$($Pool_Currency -replace "_.+$")")$(if ($Pool_Currency -match "GRIN") {"/"} else {"."}){workername:$Worker}"
                Pass          = "x"
                Region        = $Pool_RegionsTable.$Pool_Region
                SSL           = $false
                Updated       = $Stat.Updated
                PoolFee       = $Pool_Fee
                DataWindow    = $DataWindow
                Workers       = $_.workers
                Hashrate      = $Stat.HashRate_Live
                #TSL           = $Pool_TSL
                BLK           = $Stat.BlockRate_Average
            }
        }
    }
}