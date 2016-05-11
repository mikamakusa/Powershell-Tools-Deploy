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

function Container {
    Param(
        [Parameter(Mandatory=$true, Position=0)][ValidateSet('Docker', 'Rkt')][string]$ToolName,
        [Parameter(Mandatory=$true, Position=1)][ValidateSet("Install","Deploy","Build","Stop","Remove")]$Action,
        [Parameter(Mandatory=$true, Position=2)][string]$name,
        [Parameter(Mandatory=$true, Position=3)][string]$image,
        [Parameter(Mandatory=$false)][ValidateSet("yes","no")][string]$daemon,
        [Parameter(Mandatory=$false)][string]$net,
        [Parameter(Mandatory=$false)][string]$addhost,
        [Parameter(Mandatory=$false)][ValidateSet("no","on-failure","always","unless-stopped")][string]$restart,
        [Parameter(Mandatory=$false)][string]$Hostname,
        [Parameter(Mandatory=$false)][string]$Network,
        [Parameter(Mandatory=$false)][string]$Volume,
        [Parameter(Mandatory=$false)][string]$Mount
        )
    if (-not($ToolName) -and (-not($Action) -and (-not($name) -and (-not($image))))) {
        Throw 'Missing parameters'
    }
    switch ($ToolName) {
        "Docker" {
            switch ($Action) {
                "Install" {
                    if ((Get-WmiObject -Class Win32_OperatingSystem).Caption -notmatch "Windows") {
                        Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "wget -qO http://get.docker.com/ | sh"
                    }
                    else {}
                }
                "Deploy" {
                    Create -name $name -image $image -daemon $daemon -net $net -addhost $addhost -restart $restart
                }
                "Build" {
                    Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "Docker Build -t "+((Import-Csv $file -Delimiter ";").IName)+" ."
                }
                "Stop" {
                    Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "docker stop "+((Import-Csv $file -Delimiter ";").CId)
                }
                "Remove" {
                    Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "docker rm "+((Import-Csv $file -Delimiter ";").CId)
                }
            }
        }
        "Rkt" {
            switch ($Action) {
                "Install" {
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

function Network {
    Param(
        [Parameter(Mandatory=$true, Position=0)][ValidateSet('Weave','Flannel')]$ToolName,
        [Parameter(Mandatory=$true, Position=1)][ValidateSet('Install','Deploy')]$Action
        )
    switch($ToolName){
        "Weave" {
            switch($Action){
                "Install" {
                    Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "curl -L git.io/weave -o /usr/local/bin/weave"
                    Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "chmod +x /usr/local/bin/weave"
                }
                "Deploy" {
                    Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "weave launch"
                }
            }
        }
        "Fannel" {
            switch($Action){
                "Install" {
                    Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "cd /home/ && git clone https://github.com/coreos/flannel.git"
                    Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "cd /home/flannel && ./build"
                }
                "Deploy" {
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

function Cluster {
    Param(
        [Parameter(Mandatory=$true, Position=0)][ValidateSet('Swarm', 'Serf', 'Fleet', 'Mesos', 'Zookeeper')][string]$ToolName,
        [Parameter(Mandatory=$true, Position=1)][ValidateSet('Install','Deploy')][string]$Action,
        [Parameter(Mandatory=$false)][ValidateSet('Master','Slave', 'Manager')][string]$Role,
        [Parameter(Mandatory=$false)][string]$Port
        )
    switch($ToolName){
        "Swarm" {
            switch($Action) {
                "Install" {
                    Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "docker pull swarm:latest"
                }
                "Deploy" {
                    if ([string]::IsNullOrWhiteSpace($Role)){
                        Throw 'Missing parameters'
                    }
                    switch($Role){
                        "Master" {
                            Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "docker -H tcp://0.0.0.0:$Port -H unix:///var/run/docker.sock -d &"
                            $IPmaster = (Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "hostname -i")
                            $SwarmToken = (Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "docker -H tcp://"$IPmaster+":"+$Port+"swarm create").Output
                            Invoke-SSHCommand -SessionId ((Get-SSHSession).SessionId) -Command "docker run swarm join"
                        }
                        "Slave" {
                            Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "docker pull swarm:latest"
                            Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "docker -H tcp://$IPclient:2375 -H unix:///var/run/docker.sock -d &"
                            $IPclient = (Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "hostname -i")
                            Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "docker -H tcp://"+$IPclient+":"+$Port+"run swan join --addr=$IPmaster token://$SwarmToken"
                        }
                        "Manager" {
                            $IPmaster = (Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "hostname -i")
                            Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "docker -H tcp://"+$IPmaster+":"+$SwarmPort+" run -d -p 5000:5000 swarm manage token://$SwarmToken"
                        }
                    }
                }
            }
        }
        "Serf" {
            switch($Action){
                "Install" {
                    Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "wget https://releases.hashicorp.com/serf/0.7.0/serf_0.7.0_linux_amd64.zip && unzip serf_0.7.0_linux_amd64.zip -d /usr/local/bin/serf"
                    Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command '"echo "PATH=$PATH:/usr/local/bin/serf" >> /root/.bashrc"'
                }
                "Deploy" {
                    if ([string]::IsNullOrWhiteSpace($Role)){
                        Throw 'Missing parameters'
                    }
                    switch($Role){
                        "Master" {
                            $hostname = (Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "hostname")
                            $IPmaster = (Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "hostname -i") 
                            Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "touch /home/serf/event.sh"
                            Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "serf agent -log-level=debug -event-handler=./home/serf/event.sh -node=$hostname -bind="+$IPmaster+":7496 -profile=wan &"
                        }
                        "Slave" {
                            $hostname = (Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "hostname")
                            $IPnode = (Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "hostname -i") 
                            Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "touch /home/serf/event.sh"
                            Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "serf agent -log-level=debug -event-handler=./home/serf/event.sh -node=$hostname -bind="+$IPnode+":7496 -rpc-addr=127.0.0.1:7373 -profile=wan &"
                            Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "serf join "+$IPmaster+":7496"
                        }
                    }
                }
            }
        }
        "Fleet" {}
        "Mesos" {}
        "Zookeeper" {}
    }
}

function Discovery {
    Param(
        [Parameter(Mandatory=$true, Position=0)][ValidateSet('Consul', 'Etcd')][string]$ToolName,
        [Parameter(Mandatory=$true, Position=1)][ValidateSet('Install','Deploy')][string]$Action,
        [Parameter(Mandatory=$false)][ValidateSet('Server', 'Agent')][string]$Role
        )
    switch($ToolName){
        "Consul" {
            switch($Action){
                "Install" {
                    Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "wget https://releases.hashicorp.com/consul/0.6.1/consul_0.6.1_linux_amd64.zip && unzip consul_0.6.1_linux_amd64.zip -d /usr/local/bin/consul"
                    Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command '"echo "PATH=$PATH:/usr/local/bin/consul" >> /root/.bashrc"'
                }
                "Deploy" {
                    if ([string]::IsNullOrWhiteSpace($Role)){
                        Throw 'Missing parameters'
                    }
                    switch($Role){
                        "Server"{
                            Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "wget https://releases.hashicorp.com/consul/0.6.4/consul_0.6.4_web_ui.zip && unzip consul_0.6.4_web_ui.zip -d /home/"
                            $IPconsulser = (Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "hostname -i")
                            Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "consul agent -data-dir consul -server -bootstrap -client $IPconsulser -advertise $IPconsulser -ui-dir /home/web_ui/ &"
                        }
                        "Agent"{
                            Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "mkdir /home/consul/service"
                            $IPconsulcli = (Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "hostname -i")
                            Invoke-SSHComand -SessionId ((Get-SSHSession).SessionId) -Command "consul agent -data-dir /root/consul -client $IPconsulcli -advertise $IPconsulcli -node webserver -config-dir /home/consul/service -join $IPconsulser"
                        }
                    }
                }
            }
        }
        "Etcd" {}
    }
}