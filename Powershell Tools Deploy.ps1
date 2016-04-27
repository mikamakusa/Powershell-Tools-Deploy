function Create {
    Param(
        [Parameter(Mandatory=$true, Position=0)][string]$name,
        [Parameter(Mandatory=$true, Position=1)][string]$image,
        [Parameter(Mandatory=$false)][ValidateSet("yes","no")][string]$daemon,
        [Parameter(Mandatory=$false)][string]$net,
        [Parameter(Mandatory=$false)][string]$addhost,
        [Parameter(Mandatory=$false)][ValidateSet("no","on-failure","always","unless-stopped")][string]$restart
    )
    $nameset = if ([string]::IsNullOrWhiteSpace($name)){}else{"--name "+$name}
    $imageset = if ([string]::IsNullOrWhiteSpace($image)){}else{$image}
    $daemonset = if ([string]$daemon -match "yes"){"-dit"}else{"-a=['STDIN'] -a=['STDOUT'] -a=['STDERR']"}
    $netset = if ([string]::IsNullOrWhiteSpace($net)){}else{"--net="+'"'+$net+'"'}
    $addhostset = if ([string]::IsNullOrWhiteSpace($addhost)){}else{"--add-hosts "+$addhost}
    $restartset = if ([string]::IsNullOrWhiteSpace($restart)){}else{"--restart="+$restart}
    Invoke-SSHCommand -SessionId 0 -Command "docker run"$restartset $daemonset $addhostset $netset $nameset $imageset
}
function Tools {
    Param(
        [Parameter(Mandatory=$true,position = 0)][ValidateSet("Container","Network","Discovery","Cluster")][string]$Type
    )
    if ($Type -match "Container") {
        Param(
            [Parameter(Mandatory=$true, Position=0)][ValidateSet("Docker","RKT")][string]$ToolName
            )
            if ($ToolName -match "Docker") {
                Param(
                    [Parameter(Mandatory=$true, Position=1)][ValidateSet("Install","Deploy","Build","Stop","Remove")]$Action
                    )
                if ($Action -match "Deploy") {
                    Param(
                    [Parameter(Mandatory=$true, Position=1)][string]$name,
                    [Parameter(Mandatory=$true, Position=2)][string]$image,
                    [Parameter(Mandatory=$false)][ValidateSet("yes","no")][string]$daemon,
                    [Parameter(Mandatory=$false)][string]$net,
                    [Parameter(Mandatory=$false)][string]$addhost,
                    [Parameter(Mandatory=$false)][ValidateSet("no","on-failure","always","unless-stopped")][string]$restart
                    )
                }
                elsif ($Action -match "Build") {
                    Param(
                        [Parameter(Mandatory=$true, Position=0)][string]$path,
                        [Parameter(Mandatory=$true, Position=1)][string]$file
                        )
                }
                elsif ($Action -match "Stop" -or "Remove") {
                    Param(
                        [Parameter(Mandatory=$true)][string]$containerid
                        )
                }
            }
            elsif ($ToolName -match "RKT") {
                Param(
                    [Parameter(Mandatory=$true, Position=1)][ValidateSet("Install","Deploy","Remove")]$Action
                    )
                if ($Action -match "Deploy") {
                    Param(
                        [Parameter(Mandatory=$true, Position=0)][ValidateSet("Docker","Rkt")][string]$From,
                        [Parameter(Mandatory=$true, Position=1)][ValidateSet("Docker","Rkt")][string]$Image,
                        [Parameter(Mandatory=$false)][string]$Hostname,
                        [Parameter(Mandatory=$false)][string]$Network,
                        [Parameter(Mandatory=$false)][string]$Volume,
                        [Parameter(Mandatory=$false)][string]$Mount
                    )
                }
            }
    }
    elsif ($Type -match "Network") {
        Param(
            [Parameter(Mandatory=$true, Position=0)][ValidateSet("Weave","Flannel")][string]$ToolName
            [Parameter(Mandatory=$true, Position=1)][ValidateSet("Install","Deploy")]$Action    
            )
    }
    switch($Type){
        "Container" {
            switch($ToolName){
                "Docker" {
                    switch ($Action){
                        "Install"{
                            if ((Get-WMIObject -Class Win32_OperatingSystem).Caption -match "Windows") {
                                Invoke-WebRequest -Uri "https://github.com/docker/toolbox/releases/download/v1.11.0/DockerToolbox-1.11.0.exe" -Outfile "c:\DockerToolbox-1.11.0.exe"
                                Start-Process "c:\DockerToolbox-1.11.0.exe" -ArgumentList "/s" -Wait; Remove-Item "c:\DockerToolbox-1.11.0.exe"
                            }
                            else {
                                Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "curl -sSL https://get.docker.com/ | sh"
                            }
                        }
                        "Deploy"{
                            if ((Get-WMIObject -Class Win32_OperatingSystem).Caption -match "Windows") {
                                # Detect Docker Toolbox installation and launch it
                                $vbox = New-Object -ComObject "VirtualBox.VirtualBox"
                                $vmachine = $vbox.FindMachine(($vbox.Machines | where {$_.Name -match "default"} | select -Property Id).id)
                                $vboxsession = New-Object -ComObject "VirtualBox.Session"
                                $vmachine.LaunchVMProcess($vboxsession,"headless","")
                                # Gather IP address and SSHPort  
                                foreach ($i in (& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' showvminfo "default" --machinereadable)) {
                                    if ($i -match "ssh") {
                                        return $i.split(",")
                                        $IP = $i.Split(",")[2]
                                        $Port = $i.Split(",")[3]
                                    }
                                }
                                # Launch connexion to VM "boot2docker"
                                $credentials = New-Object System.Management.Automation.PSCredential($username,$password)
                                New-SSHSession -ComputerName $IP -Credentials docker -Port $Port -KeyFile "C:\Users\$env:USERNAME\.docker\machine\machines\default\id_rsa"
                                Create -name $nameset -image $imageset -daemon $daemonset -net $netset -addhost $addhostset -restart $restartset
                                }                         
                            else {
                                Create -name $nameset -image $imageset -daemon $daemonset -net $netset -addhost $addhostset -restart $restartset
                            }
                        }
                        "Build" {
                            New-SFTPItem -Path $path+$file -SessionId ((Get-SSHSession).SessionId) -ItemType file
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "Docker Build -t "+$file+"."
                        }
                        "Stop" {
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "docker stop "+$containerid
                        }
                        "Remove" {
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "docker rm "+$containerid
                        }
                    }
                }
                "Rkt" {
                    switch ($Action){
                        "Install"{
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "cd /home/ && wget https://github.com/coreos/rkt/releases/download/v0.9.0/rkt-v0.9.0.tar.gz && tar xzf rkt-v0.9.0.tar.gz"
                        }
                        "Deploy" {
                            $From = if ((Import-Csv $file -Delimiter ";") -match "Docker") {"--insecure-options=image"}else{}
                            $Image = if ($From -match "Docker") {return "docker://"+((Import-Csv $file -Delimiter ";").Image)}else {return ((Import-Csv $file -Delimiter ";").Image)}
                            $Volume = if ([string]::IsNullOrWhiteSpace((Import-Csv $file -Delimiter ";").Volumes)){}else{"--volume "+((Import-Csv $file -Delimiter ";").Volumes)}
                            $Network = if ([string]::IsNullOrWhiteSpace((Import-Csv $file -Delimiter ";").Network)){}else{"--net="+((Import-Csv $file -Delimiter ";").Network)}
                            $Hostname = if ([string]::IsNullOrWhiteSpace((Import-Csv $file -Delimiter ";").Hostname)){}else{"--hostname "+((Import-Csv $file -Delimiter ";").Hostname)}
                            $Mount = if ([string]::IsNullOrWhiteSpace((Import-Csv $file -Delimiter ";").Mount)){}else{"--mount "+((Import-Csv $file -Delimiter ";").Mount)}
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "rkt run --interactive $Image $From $Volume $Network $Hostname $Mount"
                        }
                        "Remove" {
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "rkt gc --grace-preiod=0"
                        }
                    }
                }
            }
        }
        "Network" {
            switch($ToolName){
                "Weave"{
                    switch($Action){
                        "Install"{
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "curl -L git.io/weave -o /usr/local/bin/weave"
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "chmod +x /usr/local/bin/weave"
                        }
                        "Deploy"{
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "weave launch"
                        }
                    }
                }
                "Flannel"{
                    switch($Action){
                        "Install"{
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "cd /home/ && git clone https://github.com/coreos/flannel.git"
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "cd /home/flannel && ./build"
                        }
                        "Deploy"{
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "./bin/flanneld &"
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "docker stop"
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "source /run/flannel/subnet.env"
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command 'ifconfig docker0 ${FLANNEL_SUBNET}'
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command 'docker daemon --bip=${FLANNEL_SUBNET} --mtu=${FLANNEL_MTU} &'
                        }
                    }
                }
            }
        }
        "Discovery" {
            
        }
        "Cluster" {
            
        }
        default {}
    }
}