#region script header
<#
.Synopsis
    Inteded for HPE products with ILO connection.
    This script will make a connection to an HP ILO and fetch ILO data.

.DESCRIPTION
    The script accepts multiple IP addresses as arguments (comma seperated).
    Before connecting to every IP, you will be prompted with a login.
    It will only read from the HP ILO and not write to it.

    If the HP server is healthy, it will show a brief overview.
    If the HP server is unhealthy, it will try to find out what is wrong and display it.

    This is made with Rest Method and is tested for ILO 4 - ILO 5
    I did not -yet- use Redfish.
    Supported from Powershell v3.0+ (server 2012 / Windows 8)

.PARAMETER
    At least one ip address or hostname (e.g. 192.168.1.100)

.NOTES
    Version: 1.0
    Author: Alex Meys
    Creation Date: 03/2020
    Link: https://github.com/alexmeys/Get-HPILO

.EXAMPLE
    Get-HPILO 10.10.10.100, 172.16.1.100, 192.168.1.100    
     
#>
#endregion

#region args
param(
[parameter(
        Mandatory         = $true,
        ValueFromPipeline = $true)]
    [string[]]$ips
)
#endregion

#region sslcert
# Skip self signed stuff for the duration of the script
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
#endregion

#region start processing

Clear-Host
Write-Host ""

$Sub_Meth = "login"
$Sub1 = "Post"
$Sub2 = "Get"

foreach ($ip in $ips)
{ 
    # You could adjust the line below for different port (default https (443))
    $Site = "https://$ip" 
    $Site += "/json/login_session"

    $Plain_Site = "https://$ip"
    
    # Credential part - prompted
    $creds = Get-Credential -Credential $null
    $u = $creds.GetNetworkCredential().username
    $p = $creds.GetNetworkCredential().Password

    $Crafted = @{'method' = "login" ; 'user_login' = $u  ; 'password' = $p;}
    $Crafted = $Crafted | ConvertTo-Json
    
    try{

        # Try Login
        $Sess = Invoke-RestMethod -Method $Sub1 -Uri $Site -Body $Crafted -SessionVariable 'Sessie'

        # If you want to, take a session key ($s1) and add code to edit/store data - not used in the -original- script
        # $s1 = $Sess.session_key
    }
    catch{

        # Fail Login
        Write-Warning "Connection or Login problem:"
        $err = $_.Exception.Message
        switch -Wildcard ($err)
        {
            Default
            {
                Write-Host ""
                Write-Host $err
                Write-Host ""
                exit 1
            }
            '*403*'
            {
                Write-Host ""
                Write-Host "It looks like you don't have permissions or mistyped the password, try again."
                Write-Host $err
                Write-Host ""
                exit 1
            }
            '*500*'
            {
                Write-Host ""
                Write-Host "It could be that you entered the wrong password too many times."
                Write-Host "It looks like you are locked out, just wait a few minutes and try again."
                Write-Host $err
                Write-Host ""
                exit 1
            }

        }
        
    }

    # Login was succesful 
    # Start processing

    $Ovw = "/json/overview"

    $pg_ovw = $Plain_Site + $Ovw
    $GenOvw = Invoke-RestMethod -Method $Sub2 -Uri $pg_ovw -WebSession $Sessie | ConvertTo-Json
    
    $hstb1 = @{}
    (ConvertFrom-Json $GenOvw).psobject.properties | Foreach {$hstb1[$_.Name] = $_.Value}


    # Show basic output - Overview
    Write-Host "------------------------------------------------------------"
    Write-Host (" Overview HP Server {0} " -f $hstb1['server_name']) -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------"
    Write-Host ""
    Write-Host ("Ilo: {0}" -f $hstb1['ilo_name'])
    Write-Host ("Ip: {0}" -f $hstb1['ip_address'])
    Write-Host ("Port: {0}" -f $hstb1['https_port'])
    Write-Host ""
    Write-Host ("Model: {0}" -f $hstb1['product_name'])
    Write-Host ("Serie Nr: {0}" -f $hstb1['serial_num'])
    Write-Host ("Firmware: {0}" -f $hstb1['ilo_fw_version'])
    Write-Host ""
    Write-Host ("Power: {0}" -f $hstb1['power'])
    Write-Host ("Date: {0}" -f $hstb1['date'])
    if ($hstb1['system_health'] -ne "OP_STATUS_OK")
    {
        Write-Host ("System Health: {0}" -f $hstb1['system_health']) -ForegroundColor Red -BackgroundColor Black
    }
    else
    {
        Write-Host ("System Health: {0}" -f $hstb1['system_health']) -ForegroundColor Green
    }

    if ($hstb1['self_test'] -ne "OP_STATUS_OK")
    {
        Write-Host ("System Health: {0}" -f $hstb1['self_test']) -ForegroundColor Red -BackgroundColor Black
        Write-Host ""
        Write-Host "There is something wrong with ILO, try these steps:"
        Write-Host "1 - Upgrade ILO version"
        Write-Host "2 - Perform NAND format"
        Write-Host "3 - Full host reboot"
        Write-Host "4 - Format NAND again"
        Write-Host "System board may need replacing, Contact HPE"
        Write-Host ""
    }
    else
    {
        Write-Host ("ILO Health: {0}" -f $hstb1['self_test']) -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "-----------------------------------"
    Write-Host ""

    # Trying to show more info if something is not healthy.
    
    if($hstb1['system_health'] -ne "OP_STATUS_OK")
    {
        Write-Host " There seems to be a hardware problem! "
        Write-Host "Check your hardware or do a firmware update. "
        Write-Host ""

        $Health = "/json/health_summary"

        $pg_health = $Plain_Site + $Health
        $HealthOvw = Invoke-RestMethod -Method $Sub2 -Uri $pg_health -WebSession $Sessie | ConvertTo-Json
    
        $hstb2 = @{}
        (ConvertFrom-Json $HealthOvw).psobject.properties | Foreach {$hstb2[$_.Name] = $_.Value}

        Foreach($key in $hstb2.keys)
        {
            if(($hstb2[$key] -eq "OP_STATUS_DEGRADED") -and ($key -ne "system_health"))
            {
                switch -Wildcard ($key)
                {
                    Default 
                    {
                        Write-Host "Nothing found, but something is wrong, go check ILO manually!"
                        exit 0
                    }
                    '*storage*'
                    {
                        # In case of storage or cache issues
                        $strg = "/json/health_phy_drives"

                        $pg_strg = $Plain_Site + $strg
                        $Errstrg = Invoke-RestMethod -Method $Sub2 -Uri $pg_strg -WebSession $Sessie | ConvertTo-Json -Depth 5

                        $NwErrstrg = $Errstrg | ConvertFrom-Json

                        $name = "name"
                        $status = "status"
                        $serial = "serial_no"
                        $model = "model"
                        $cap = "capacity"
                        $pstatus = "phys_status"
                        $indexnr = "phys_idx"

                        $stype = "storage_type"
                        $sname = "name"
                        $shwstatus = "hw_status"
                        $sserial = "serial_no"
                        $smodel = "model"
                        $sfw = "fw_version"
                        $scond = "accel_cond"
                        $sbtsn = "accel_serial"


                        $physical_drives = "physical_drives"
                        $phy_drive_arrays = "phy_drive_arrays"

                        $pathArr = $NwErrstrg.$phy_drive_arrays

                        for ($i=0; $i -le $pathArr.Length-1; $i++)
                        {
                            Write-Host ("---- Cache: {0} ----" -f $pathArr[$i].$smodel)
                            Write-Host ""
                            Write-Host "Cache Name: " -NoNewline 
                            Write-Host $pathArr.$sname[$i]
                            Write-Host "Cache Type: " -NoNewline
                            Write-Host $pathArr.$stype[$i]
                            Write-Host "Cache Serial: " -NoNewline
                            Write-Host $pathArr.$sserial[$i]
                            Write-Host "Cache Model: " -NoNewline
                            Write-Host $pathArr.$smodel[$i]
                            Write-Host "Cache Firmware: " -NoNewline
                            Write-Host $pathArr.$sfw[$i]
                            
                            if($pathArr.$shwstatus[$i] -ne 'OP_STATUS_OK')
                            {
                                Write-Host "Cache controller HW status: " -NoNewline -ForegroundColor Red -BackgroundColor Black
                                Write-Host $pathArr.$shwstatus[$i] -ForegroundColor Red
                            }
                            else
                            {
                                Write-Host "Cache controller HW status: " -NoNewline -ForegroundColor Green
                                Write-Host $pathArr.$shwstatus[$i] -ForegroundColor Green
                            }
                            if($pathArr.$scond[$i] -eq $null)
                            {
                                Write-Host "Cache Battery: No battery present" -ForegroundColor Green
                            }
                            elseif($pathArr.$scond[$i] -ne 'OP_STATUS_OK')
                            {
                                Write-Host "Cache Battery: " -NoNewline -ForegroundColor Red -BackgroundColor Black
                                Write-Host $pathArr.$scond[$i] -ForegroundColor Red -BackgroundColor Black
                                Write-Host "Cache Battery S/N: " -NoNewline
                                Write-Host $pathArr.$sbtsn[$i]
                            }
                            else
                            {
                                Write-Host "Cache Battery: " -NoNewline -ForegroundColor Green
                                Write-Host $pathArr.$scond[$i] -ForegroundColor Green
                                Write-Host "Cache Battery S/N: " -NoNewline
                                Write-Host $pathArr.$sbtsn[$i]
                            }

                            Write-Host ""
                            Write-Host "----Disks----"
                            Write-Host ""

                            for ($j = 0; $j -le $NwErrstrg.$phy_drive_arrays[$i].$physical_drives.Length-1 ; $j++)
                            {
                                Write-Host "Name: " -NoNewline
                                Write-Host $NwErrstrg.$phy_drive_arrays[$i].$physical_drives.$name[$j]
                                Write-Host "Model: " -NoNewline
                                Write-Host $NwErrstrg.$phy_drive_arrays[$i].$physical_drives.$model[$j]
                                Write-Host "Serial: " -NoNewline
                                Write-Host $NwErrstrg.$phy_drive_arrays[$i].$physical_drives.$serial[$j]

                                if($NwErrstrg.$phy_drive_arrays[$i].$physical_drives.$status[$j] -ne 'OP_STATUS_OK')
                                {
                                    Write-Host "Status: " -NoNewline -ForegroundColor Red -BackgroundColor Black
                                    Write-Host $NwErrstrg.$phy_drive_arrays[$i].$physical_drives.$status[$j] -ForegroundColor Red -BackgroundColor Black
                                }
                                else
                                {
                                    Write-Host "Status: " -NoNewline -ForegroundColor Green
                                    Write-Host $NwErrstrg.$phy_drive_arrays[$i].$physical_drives.$status[$j] -ForegroundColor Green
                                }

                                if($NwErrstrg.$phy_drive_arrays[$i].$physical_drives.$pstatus[$j] -ne 'PHYS_OK') 
                                {
                                    Write-Host "Status: " -NoNewline -ForegroundColor Red -BackgroundColor Black
                                    Write-Host $NwErrstrg.$phy_drive_arrays[$i].$physical_drives.$pstatus[$j] -ForegroundColor Red -BackgroundColor Black
                                }
                                else
                                {
                                    Write-Host "Status: " -NoNewline -ForegroundColor Green
                                    Write-Host $NwErrstrg.$phy_drive_arrays[$i].$physical_drives.$pstatus[$j] -ForegroundColor Green
                                }
                                Write-Host "Phsycial Status: " -NoNewline
                                Write-Host 
                            
                                Write-Host "Capacity: " -NoNewline
                                Write-Host $NwErrstrg.$phy_drive_arrays[$i].$physical_drives.$cap[$j]
                                Write-Host "Index Nr: " -NoNewline
                                Write-Host $NwErrstrg.$phy_drive_arrays[$i].$physical_drives.$indexnr[$j]
                                Write-Host ""
                                
                            }

                            
                         }
                         break

                    }
                    '*fans*'
                    {
                        # In case there is a fan issue
                        $Fans = "/json/health_fans"

                        $pg_fans = $Plain_Site + $Fans
                        $FansOvw = Invoke-RestMethod -Method $Sub2 -Uri $pg_fans -WebSession $Sessie | ConvertTo-Json

                        $errFans = $FansOvw| ConvertFrom-Json

                        $fanz = "fans"
                        $label = "label"
                        $status = "status"
                        $speed = "speed"

                        $NwErrFans = $errFans.$fanz
    
                        for ($i = 0 ; $i -le $NwErrFans.Length-1; $i++)
                        {
                            Write-Host $NwErrFans.$label[$i]
                            Write-Host $NwErrFans.$speed[$i] -NoNewline
                            Write-Host " %"
                            if($NwErrFans.$status[$i] -ne "OP_STATUS_OK")
                            {
                                Write-Host $NwErrFans.$status[$i] -ForegroundColor Red -BackgroundColor Black
                            }
                            else
                            {
                                Write-Host $NwErrFans.$status[$i] -ForegroundColor Green
                            }
                            Write-Host ""

                        }
                        break
                    }
                    '*power*'
                    {
                        # In case there is a power issue
                        $Pwr = "/json/power_supplies"

                        $pg_stroom = $Plain_Site + $Pwr
                        $PwrOvw = Invoke-RestMethod -Method $Sub2 -Uri $pg_stroom -WebSession $Sessie | ConvertTo-Json -Depth 5
    
                        $errPwr = $PwrOvw | ConvertFrom-Json

                        $currW = "present_power_reading"
                        $supplies = "supplies"

                        $enabled = "enabled"
                        $health = "unhealthy"
                        $bay = "ps_bay"
                        $pscond = "ps_condition"
                        $pspresent = "ps_present"
                        $pserror = "ps_error_code"
                        $psmodel = "ps_model"
                        $psspare = "ps_spare"
                        $psserial = "ps_serial_num"
                        $psmax = "ps_max_cap_watts"
                        $psinput = "ps_input_volts"
                        $psoutput = "ps_output_watts"

                        $NwErrPwr = $errPwr.$supplies

                        Write-Host ""
                        Write-Host ("Current Watt: {0}" -f $errPwr.$currW)
                        Write-Host ""

                        for ($i = 0 ; $i -le $NwErrPwr.Length-1; $i++)
                        {
                            Write-Host "Model: " -NoNewline
                            Write-Host $NwErrPwr.$psmodel[$i]
                            Write-Host "Serial: " -NoNewline
                            Write-Host $NwErrPwr.$psserial[$i]
                            Write-Host "Active: " -NoNewline
                            Write-Host $NwErrPwr.$enabled[$i]
                            if($NwErrPwr.$health[$i] -eq 0)
                            {
                                Write-Host "Health: " -NoNewline
                                Write-Host $NwErrPwr.$health[$i] -NoNewline
                                Write-Host " " -NoNewline
                                Write-Host "Healthy."
                            }
                            else
                            {
                                Write-Host "Health: " -NoNewline -ForegroundColor Red -BackgroundColor Black
                                Write-Host $NwErrPwr.$health[$i] -ForegroundColor Red -BackgroundColor Black
                            }
                            Write-Host "Bay: " -NoNewline
                            Write-Host $NwErrPwr.$bay[$i]
                            if($NwErrPwr.$pspresent[$i] -ne "PS_YES")
                            {
                                Write-Host "Present: " -NoNewline -ForegroundColor Red -BackgroundColor Black
                                Write-Host $NwErrPwr.$pspresent[$i] -ForegroundColor Red -BackgroundColor Black
                            }
                            else
                            {
                                Write-Host "Present: " -NoNewline -ForegroundColor Green
                                Write-Host $NwErrPwr.$pspresent[$i] -ForegroundColor Green
                            }

                            if($NwErrPwr.$pscond[$i] -ne "PS_OK")
                            {
                                Write-Host "Present: " -NoNewline -ForegroundColor Red -BackgroundColor Black
                                Write-Host $NwErrPwr.$pscond[$i] -ForegroundColor Red -BackgroundColor Black
                            }
                            else
                            {
                                Write-Host "Present: " -NoNewline -ForegroundColor Green
                                Write-Host $NwErrPwr.$pscond[$i] -ForegroundColor Green
                            }
                            if($NwErrPwr.$pserror[$i] -ne "PS_GOOD_IN_USE")
                            {
                                Write-Host "Error: " -NoNewline -ForegroundColor Red -BackgroundColor Black
                                Write-Host $NwErrPwr.$pserror[$i] -ForegroundColor Red -BackgroundColor Black
                            }
                            else
                            {
                                Write-Host "Error: " -NoNewline -ForegroundColor Green
                                Write-Host $NwErrPwr.$pserror[$i] -ForegroundColor Green
                            }
        
                            Write-Host "Spare: " -NoNewline
                            Write-Host $NwErrPwr.$psspare[$i]
                            Write-Host "Max: " -NoNewline
                            Write-Host $NwErrPwr.$psmax[$i]
                            Write-Host "Input: " -NoNewline
                            Write-Host $NwErrPwr.$psinput[$i]
                            Write-Host "Output: " -NoNewline
                            Write-Host $NwErrPwr.$psoutput[$i]
                            Write-Host "-----------------"
                            Write-Host " "

                        }
                        break
                    }
                    '*mem*'
                    {
                        # In case there is a memory issue
                        $Mem = "/json/mem_info"

                        $pg_mem = $Plain_Site + $Mem
                        $MemOvw = Invoke-RestMethod -Method $Sub2 -Uri $pg_mem -WebSession $Sessie | ConvertTo-Json

                        $errMem = $MemOvw| ConvertFrom-Json

                        $memory = "mem_modules"

                        $memcpu = "mem_cpu_num"
                        $memmod = "mem_mod_num"
                        $memidx = "mem_mod_idx"
                        $memsize = "mem_mod_size"
                        $memtype = "mem_mod_type"
                        $memtech = "mem_mod_tech"
                        $memfreq = "mem_mod_frequency"
                        $memstatus = "mem_mod_status"
                        $memcond = "mem_mod_condition"
                        $mempart = "mem_mod_part_num"
                        $memporttype = "mem_type_active"

                        $NwErrMem = $errMem.$memory

                        Write-Host ""
                        Write-Host ("Memory Type: {0}" -f $errMem.$memporttype )

                        for ($i = 0 ; $i -le $NwErrMem.Length-1; $i++)
                        {
                            if(($NwErrMem.$memstatus[$i] -eq "MEM_NOT_PRESENT") -and ($NwErrMem.$memcond[$i] -eq "MEM_OTHER"))
                            {
                                Write-Host "Free Index nr: " -NoNewline
                                Write-Host $NwErrMem.$memidx[$i]
                                Write-Host "Free Module nr: " -NoNewline
                                write-Host $NwErrMem.$memmod[$i]
                                Write-host ""

                            }
                            else
                            {
                                Write-Host "---------------------"
                                Write-Host "Index: " -NoNewline
                                Write-Host $NwErrMem.$memidx[$i]
                                Write-Host "Size: " -NoNewline
                                write-Host $NwErrMem.$memsize[$i]
                                Write-Host "Serial: " -NoNewline
                                write-Host $NwErrMem.$mempart[$i]
                                Write-Host "Type: " -NoNewline
                                write-Host $NwErrMem.$memtype[$i]
                                Write-Host "Tech: " -NoNewline
                                write-Host $NwErrMem.$memtech[$i]
                                Write-Host "Frequency: " -NoNewline
                                write-Host $NwErrMem.$memfreq[$i]
                                Write-Host "Module Num: " -NoNewline
                                write-Host $NwErrMem.$memmod[$i]
                                Write-Host "Module Cpu Num: " -NoNewline
                                write-Host $NwErrMem.$memcpu[$i]

                                if($NwErrMem.$memstatus[$i] -ne "MEM_GOOD_IN_USE")
                                {
                                    Write-Host "Module status: " -NoNewline -ForegroundColor Red -BackgroundColor Black
                                    write-Host $NwErrMem.$memstatus[$i] -ForegroundColor Red -BackgroundColor Black
                                }
                                else 
                                {
                                    Write-Host "Module status: " -NoNewline -ForegroundColor Green
                                    write-Host $NwErrMem.$memstatus[$i] -ForegroundColor Green
                                }
                                if($NwErrMem.$memcond[$i] -ne "MEM_OK")
                                {
                                    Write-Host "Module Condition: " -NoNewline -ForegroundColor Red -BackgroundColor Black
                                    write-Host $NwErrMem.$memcond[$i] -ForegroundColor Red -BackgroundColor Black
                                }
                                else
                                {
                                    Write-Host "Module Condition: " -NoNewline -ForegroundColor Green
                                    write-Host $NwErrMem.$memcond[$i] -ForegroundColor Green
                                }
                                Write-Host "-----------------------"
                            }
                        }
                        break
                    }
                    '*temperature*'
                    {
                        # In case there is a temperature issue
                        $Temp = "/json/health_temperature"

                        $pg_temp = $Plain_Site + $Temp
                        $TempOvw = Invoke-RestMethod -Method $Sub2 -Uri $pg_temp -WebSession $Sessie | ConvertTo-Json

                        $errTemp = $TempOvw| ConvertFrom-Json

                        $temperature = "temperature"

                        $label = "label"
                        $status = "status"
                        $reading = "currentreading"
                        $caution = "caution"
                        $unit = "temp_unit"
                        $loc = "location"

                        $NwErrTemp = $errTemp.$temperature

                        for ($i = 0 ; $i -le $NwErrTemp.Length-1; $i++)
                        {
                            if($NwErrTemp.$status[$i] -eq "OP_STATUS_ABSENT"){}
                            else
                            {
                                Write-host "------------"
                                Write-Host ""
                                Write-Host "Label: " -NoNewline
                                Write-Host $NwErrTemp.$label[$i]
                                Write-host "Location: " -NoNewline
                                Write-Host $NwErrTemp.$loc[$i]
                                Write-Host "High Temperature: " -NoNewline
                                Write-Host $NwErrTemp.$caution[$i] -NoNewline
                                Write-Host " " -NoNewline
                                Write-Host $NwErrTemp.$unit[$i] 
        
                                if ($NwErrTemp.$status[$i] -ne "OP_STATUS_OK")
                                {
                                    Write-Host "Status: " -ForegroundColor Red -BackgroundColor Black -NoNewline
                                    Write-Host $NwErrTemp.$status[$i] -ForegroundColor Red -BackgroundColor Black
                                }
                                else
                                {
                                    Write-Host "Status: " -ForegroundColor Green -NoNewline
                                    Write-Host $NwErrTemp.$status[$i] -ForegroundColor Green
                                } 
                                if ($NwErrTemp.$reading[$i] -lt $NwErrTemp.$caution[$i])
                                {
                                    Write-Host "Temperature: " -NoNewline -ForegroundColor Green
                                    Write-Host $NwErrTemp.$reading[$i] -ForegroundColor Green -NoNewline
                                    Write-Host " " -NoNewline
                                    Write-Host $NwErrTemp.$unit[$i] -ForegroundColor Green
                                }
                                elseif ($NwErrTemp.$caution[$i] -eq 0)
                                {
                                    Write-Host "Temperature: " -NoNewline -ForegroundColor Green
                                    Write-Host $NwErrTemp.$reading[$i] -ForegroundColor Green -NoNewline
                                    Write-Host " " -NoNewline
                                    Write-Host $NwErrTemp.$unit[$i] -ForegroundColor Green
                                }
                                else
                                {
                                    Write-Host "Temperature: " -NoNewline -ForegroundColor Red -BackgroundColor Black
                                    Write-Host $NwErrTemp.$reading[$i] -ForegroundColor Red -NoNewline -BackgroundColor Black
                                    Write-Host " " -NoNewline
                                    Write-Host $NwErrTemp.$unit[$i] -ForegroundColor Red -BackgroundColor Black
                                }
                                Write-Host ""
                                Write-Host "----------"
                            }

                        }
                        break
                    }
                    '*cpu*'
                    {
                        # In case there is a CPU issue
                        $Cpu = "/json/proc_info"

                        $pg_cpu = $Plain_Site + $Cpu
                        $CpuOvw = Invoke-RestMethod -Method $Sub2 -Uri $pg_cpu -WebSession $Sessie | ConvertTo-Json

                        $errCpu = $CpuOvw| ConvertFrom-Json

                        $processors = "processors"
                        $socknum = "proc_socket"
                        $name = "proc_name"
                        $speed = "proc_speed"
                        $coresAct = "proc_num_cores_enabled"
                        $cores = "proc_num_cores"
                        $threads = "proc_num_threads"
                        $tech = "proc_mem_technology"
                        $status = "proc_status"

                        $NwErrCpu = $errCpu.$processors

                        for ($i = 0 ; $i -le $NwErrcPU.Length-1; $i++)
                        {
                            Write-Host "Processor nummer: " -NoNewline
                            Write-Host $NwErrCpu.$socknum[$i]
                            Write-Host "Type CPU: " -NoNewline
                            Write-Host $NwErrCpu.$name[$i]
                            Write-Host $NwErrCpu.$tech[$i]
                            Write-Host "Speed: " -NoNewline
                            Write-Host $NwErrCpu.$speed[$i]
                            Write-Host "Cores: " -NoNewline
                            Write-Host $NwErrCpu.$cores[$i]
                            Write-Host "Cores Active: " -NoNewline
                            Write-Host $NwErrCpu.$coresAct[$i]
                            Write-Host "Threads: " -NoNewline
                            Write-Host $NwErrCpu.$threads[$i]

                            if($NwErrCpu.$status[$i] -ne "OP_STATUS_OK")
                            {
                                Write-Host "Status: " -ForegroundColor Red -BackgroundColor Black -NoNewline
                                Write-Host $NwErrCpu.$status[$i] -ForegroundColor Red -BackgroundColor Black
                            }
                            else
                            {
                                Write-Host "Status: " -ForegroundColor Green -NoNewline
                                Write-Host $NwErrCpu.$status[$i] -ForegroundColor Green
                            }
                            Write-Host ""
                        }
                        break
                    }

                }
            }
        }

    }

}
#endregion
