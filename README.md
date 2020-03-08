# Get-HPILO
Get's the health status from HP ILO interface and shows a brief overview. <br/>
In case of a problem, it will show more details about the problem and what is causing it. 

The script accepts multiple IP addresses as arguments (comma seperated). <br/>
Before connecting to an IP, you will be prompted with a login.<br/>
It will only read from the HP ILO interface and not write to it.<br/>

If the HPE server is healthy, it will show a brief overview. <br/>
If the HPE server is unhealthy, it will try to find out what is wrong and display it. <br/>

This is made with Rest Method and is tested for ILO 4 - ILO 5 <br/>
I did not -yet- use Redfish. <br/>
Supported from Powershell v3.0+ (server 2012 / Windows 8)<br/>
    
A pictures to show some example outputs:<br/>

Executing:<br/>
![](images/Get-HPILO_exec.png)   
![](images/Get-HPILO_exec1.png)

Result in case of no problems: <br/>
![](images/Get-HPILO_res.png)

Result in case of a problem: <br/>
![](images/Get-HPILO_res1.png)
![](images/Get-HPILO_res1b.png)
