Param(
  [Parameter(Mandatory=$true)][string]$vserver, # Hostname or IP to vcenter server
  [Parameter(Mandatory=$true)][string]$user, # Username used when logging in to vcenter server
  [Parameter(Mandatory=$true)][string]$password, # Password used when logging in to vcenter server
  [Parameter(Mandatory=$true)][string]$location, # Datacenter, cluster or resource group to use
  [Parameter(Mandatory=$true)][string]$bu_regexp, # Regexp that identifies backup snapshots
  [Parameter(Mandatory=$true)][int]$agelimit_bu, # Limit in hours when BU snapshots are considered old
  [Parameter(Mandatory=$true)][int]$agelimit_other, # Limit in days when regular snapshots are considered old
  [Parameter(Mandatory=$true)][int]$climit # Limit for how many snapshots one VM may have
)

# Search for VMWare PowerCLI and load it if available. Raise critical
# error if not.
If (-not (Get-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) {
  Try {
    Add-PSSnapin VMware.VimAutomation.Core -ErrorAction Stop
  }
  Catch {
    Write-Host "CRITICAL: Unable to load PowerCLI, is it installed?"
    Exit 2
  }
}

# Connect to the vcenter server. Raise critical error if it fails.
Try {
  Connect-VIServer -Server $vserver -User $user -Password $password -ErrorAction Stop | Out-Null
}
Catch {
  Write-Host "CRITICAL: Unable to connect to vcenter server."
  Exit 2
}

# Get all virtual machines in 'location' (location can be datacenter, cluster
# or resource group). Raise critical error if no virtual machine is found.
Try {
  [array]$vmachines = Get-VM -Location $location -ErrorAction stop
}
Catch {
  Write-Host "CRITICAL: No virtual machines found. Check location argument."
  Exit 2
}

# Global variable initialization
$now = Get-Date # now
$warnArray = @() # Array used to store hosts with old snapshots
$critArray = @() # Array used to store hosts with too many snapshots
$sntotal=0 # Total number of snapshots, used for OP5 performance graph

ForEach($vm in $vmachines) {
  $sncount=0
  $oldcount=0
  $vmtrunc = $vm -ireplace "^(.{30}).*$", '$1 ...'

  ForEach($sn in ($vm | get-snapshot)){

    if ($sn.Name -match $bu_regexp) {
      $limit = $sn.Created.AddHours($agelimit_bu)
    }
    else {
      $limit = $sn.Created.AddDays($agelimit_other)
    }
    If ($limit -lt $now) {
      $oldcount++
    }
    $sncount++
  }

  $sntotal += $sncount

  if ($sncount -gt $climit) {
    $critArray += "'$vmtrunc' ($sncount)"
  }

  if ($oldcount -gt 0)
  {
    $warnArray += "'$vmtrunc' ($oldcount)"
  }
}

$warnStr = $warnArray -join ', '
$critStr = $critArray -join ', '

if ($critArray.Count -gt 0) {
  $outStr = "CRITICAL: VMs has too many snapshots: $critStr."
  if ($warnArray.Count -gt 0) {
    $outStr = $outStr + " In addition a warning for old snapshots has been triggered: $warnStr"
  }
  write-host "$outStr|snapshots=${sntotal};0;0;0;0"
  Exit 2
}
elseif ($warnArray.Count -gt 0) {
  write-host "WARNING: Old snapshots found: $warnStr|snapshots=${sntotal};0;0;0;0"
  Exit 1
}

Write-Host "OK: No old snapshots found.|snapshots=${sntotal};0;0;0;0"
Exit 0
