function Tools {
    Param(
        [Parameter(Mandatory=$true,position = 0)][ValidateSet("Container","Network","Discovery","Cluster")]$Type,
        [Parameter(Mandatory=$true,position = 1)][string]$Name,
        [Parameter(Mandatory=$true,position = 1)][string]$Platform
    )
    switch($Type){
        "Container" {
            switch($Name){
                "Docker" {
                    switch($Platform) {
                        "Windows" {
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
                        }
                        "Linux" {
                            
                        }
                    }
                }
            }
        }
        "Network" {
            
        }
        "Discovery" {
            
        }
        "Cluster" {
            
        }
        default {}
    }
}