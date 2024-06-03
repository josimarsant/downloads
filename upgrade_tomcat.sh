#Script para atualização de tomcat
#Criado por Josimar
#!/bin/bash

move() {
    #echo "Source: $1"
    #echo "Dest: $2"
    destinationfolder="$1/$2"
    echo "####### moving old folder #######"
    echo "Destination: $destinationfolder"
    mkdir $destinationfolder
    find $1 -mindepth 1 -maxdepth 1 -not -name $2 -not -name $3 -not -name $4 -exec mv {} $destinationfolder \;

}

backup() {
    # Make backup of current tomcat folder
    catalinalog="$1/logs/catalina.out"
    bkpfolder="/root/bkp_tomcat"
    mkdir $bkpfolder
    echo "-------------------------------------------"
    echo "Cleaning log catalina.out......"
    echo >$catalinalog
    echo "-------------------------------------------"
    echo "Making backup on: $bkpfolder"
    cp -R $1 $bkpfolder
    cp $2 $bkpfolder
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

update() {
    systemdfolder="/etc/systemd/system"
    tomcatversion="9.0.89"
    cat $systemdfolder/$tomcatsvcname.service | grep 'WorkingDirectory' | cut -d= -f2 | sed 's/[[:space:]]//g' | grep running
    if [ $? -eq 0 ]; then
        #Running word found!
        tomcatdir=$(cat $systemdfolder/$tomcatsvcname.service | grep 'WorkingDirectory' | cut -d= -f2 | awk -F '/running' '{print $1}')
    else
        #Running word not found!
        tomcatdir=$(cat $systemdfolder/$tomcatsvcname.service | grep 'WorkingDirectory' | cut -d= -f2 | sed 's/[[:space:]]//g')
    fi

    tomcatrunning="$tomcatdir/running"
    webapps="$tomcatdir/$tomcatversion/webapps"
    tomcatservice="$systemdfolder/$tomcatsvcname.service"
    java_home=$(java -XshowSettings:properties -version 2>&1 >/dev/null | grep 'java.home' | cut -d= -f2 | sed 's/^[[:blank:]]*//')
    tomcat_memory=$(grep -o 'Xmx[^*]*' $tomcatservice | grep -oP '(?<=Xmx)\d+(?=M)')
    tomcat_xms=$(grep -o 'Xms[^*]*' $tomcatservice | grep -oP '(?<=Xms)\d+(?=M)')
    actualtomcatversion=$(java -cp $tomcatdir/lib/catalina.jar org.apache.catalina.util.ServerInfo | grep 'Server version' | awk -F 'Server version: Apache Tomcat/' '{print $2}')

    backup $tomcatdir $tomcatservice
    if [ "$?" = '0' ]; then
        echo "Backup completed"
    else
        echo "Backup not completed"
    fi

    echo "----------------- RESUMO da ATUALIZAÇÂO ------------------------------------------"
    printf "$tomcatsvcname \n  "
    echo "tomcatdir: $tomcatdir"
    echo "Tomcat Version to Install: $tomcatversion"
    echo "Tomcat Running new Folder: $tomcatrunning"
    echo "Actual tomcat Memory: $tomcat_memory"
    echo "Actual tomcat version: $actualtomcatversion"
    echo "-----------------------------------------------------------------------------------"

    echo "Confirma atualização? y/n"
    read -p "R:" confirm
    if [ $confirm == "y" ]; then
        echo "Confirmed"
        #Stop service
        systemctl stop $tomcatsvcname

        # Creating folder
        cd $tomcatdir
        sudo mkdir running >/dev/null
        sudo rm -R $tomcatversion
        sudo mkdir $tomcatversion && cd $tomcatversion

        #Download the version of tomcat:
        sudo wget https://archive.apache.org/dist/tomcat/tomcat-9/v$tomcatversion/bin/apache-tomcat-$tomcatversion.tar.gz

        #extract content:
        sudo tar -xzf apache-tomcat-$tomcatversion.tar.gz --strip-components=1

        #create tomcat user:
        id -u tomcat &>/dev/null || sudo useradd -r -m -U -d $tomcatdir -s /bin/false tomcat

        # remove old an create new symbolic  links
        sudo rm -R $tomcatrunning/*
        sudo ln -s $tomcatdir/$tomcatversion/* $tomcatrunning
        # Now, if you wish to install Tomcat on Linux with a newer version in future, simply unpack the new archive and change the symbolic link so that it points to the new version.

        #Copy server.xml

        #Adjust directory permissions:
        sudo chown -R tomcat: $tomcatdir*

        #update executables permissions:
        sudo chmod +x $tomcatrunning/bin/*.sh

        #Create systemd service:

        cat <<EOF >$systemdfolder/$tomcatsvcname.service
[Unit]
Description=Tomcat 9 se{{ let container
After=network.target

[Service]
Type=forking
WorkingDirectory=$tomcatrunning
User=tomcat
Group=tomcat
Environment="JAVA_HOME=$java_home"
Environment="JAVA_OPTS=-Djava.security.egd=file:///dev/urandom"
Environment="CATALINA_BASE=$tomcatrunning"
Environment="CATALINA_HOME=$tomcatrunning"
Environment="CATALINA_PID=$tomcatrunning/temp/$tomcatsvcname.pid"
Environment="CATALINA_OPTS=-Xms${tomcat_xms}M -Xmx${tomcat_memory}M -server -XX:+UseParallelGC"
ExecStart=$tomcatrunning/bin/startup.sh
ExecStop=$tomcatrunning/bin/shutdown.sh

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        sudo systemctl enable $tomcatsvcname
        sudo rm -R $webapps/*
        sudo cp $tomcatdir/webapps/*.war $webapps/
        sudo cp $tomcatdir/conf/server.xml $tomcatdir/$tomcatversion/conf/server.xml
        # Move old folder
        echo "------------------ Moving ---------------------------"
        move $tomcatdir $actualtomcatversion running $tomcatversion

        #Start service
        sudo systemctl start $tomcatsvcname
        sudo systemctl status $tomcatsvcname

    else
        echo "skip"
        exit 1
    fi

}

tomcatsvc() {
    systemctl list-unit-files --type=service | grep \.service | grep tomcat | awk -F '.service' '{print $1}'
}

myArray=$(tomcatsvc)

if [[ -z "$myArray" ]]; then
    echo "No Tomcat services found."
    exit 1
fi

echo "Tomcat services:"
echo "$myArray" | nl -w 2 -s '. '

echo "Digite quais versões serão atualizadas separado por espaços.(e.g., 1 2 3):"
read -p "Opção escolhida: " choices

for choice in $choices; do
    tomcatsvcname=$(echo "$myArray" | sed -n "${choice}p")
    if [[ -n "$tomcatsvcname" ]]; then
        echo "tomcat escolhido: $choice:"
        update
    else
        echo "Invalid choice: $choice"
    fi

done

#TOdo:
# test if runnning
