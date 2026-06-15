#!/bin/bash

#-----------------------------------------------------------------------------------------------------------------------#
# Step 0 : Functions Declaration                                                                                        #
# Description : This section is dedicated to the Declaration of functions that will be used later in our scripts.       #
#-----------------------------------------------------------------------------------------------------------------------#
# This function takes a step as parameter (exampe etap 1), then the service name (example docker), 
# then confirms whether or not the service has been installed.
# 
# Write By : Hermann90 for Utrains                                                                                      #                                                                                             

GREEN_COLOR_SUCCESS='\033[1;32m'
CYAN_COLOR_STARTING='\033[1;36m'
RED_COLOR_FAILLED='\033[1;31m'
COLOR_RESET_OF='\033[0m'

JAVA_AND_MAVEN_PATH_FILE=java_path.sh
PROFILES_USERS_DIR=/etc/profile.d

echo -e "${CYAN_COLOR_STARTING}>>>>>>>>>>>>>>>> JAVA AND MAVEN INSTALLATION <<<<<<<<<<<<<<<< ${COLOR_RESET_OF}"

confirm_installation_step () {
	if [ $? -eq 0 ]; then
		echo "${GREEN_COLOR_SUCCESS} >>>>>>>>>>>>>>>> $1 : $2 SUCESS <<<<<<<<<<<<<<<<"
		echo -e "${GREEN_COLOR_SUCCESS} $2 is installed Successfully ${COLOR_RESET_OF}"
		echo ">>>>>>>>>>>>>>>> Thanks to configure $2 <<<<<<<<<<<<<<<<"
	else
		echo "${RED_COLOR_FAILLED} **************** $1 : Service $2 Failled ****************"
		echo "${RED_COLOR_FAILLED} Sorry, we can't continue with this installation. Please check why the $2 service has not been installed."
		exit 1
	fi
}

MAVEN_PATH=/opt/maven



# Step 1 : Install Java 17, and config JAVA_HOME environment variable
echo -e "${CYAN_COLOR_STARTING}---------------- STEP 1 : JAVA INSTALLATION ---------------- ${COLOR_RESET_OF}"

sudo dnf install -y java-17-amazon-corretto java-17-amazon-corretto-devel


echo -e "${CYAN_COLOR_STARTING}---------------- STEP 2 : MAVEN INSTALLATION ---------------- ${COLOR_RESET_OF}"

# Download maven to /tmp directory then untar it on /opt after creating a symbolic link
wget https://dlcdn.apache.org/maven/maven-3/3.9.11/binaries/apache-maven-3.9.11-bin.tar.gz -P /tmp
sudo tar -xzf /tmp/apache-maven-3.9.11-bin.tar.gz -C /opt
sudo ln -sf /opt/apache-maven-3.9.11 $MAVEN_PATH


echo -e "${CYAN_COLOR_STARTING}>>>>>>>>>>>>>>>> JAVA AND MAVEN ENVIRONMENT CONFIGURATION <<<<<<<<<<<<<<<< ${COLOR_RESET_OF}"

JAVA_PATH=$(find /usr/lib/jvm/java-17* | head -n 1)
export JAVA_HOME=$JAVA_PATH
export M2_HOME=$MAVEN_PATH
export PATH=${JAVA_HOME}:${M2_HOME}/bin:${PATH}

### Configure the path variable 
cat > /tmp/$JAVA_AND_MAVEN_PATH_FILE << EOF
# Configuration file for java path
export JAVA_HOME=$JAVA_PATH
export M2_HOME=$MAVEN_PATH
export PATH=${JAVA_HOME}:${M2_HOME}/bin:${PATH}
EOF

sudo cp /tmp/$JAVA_AND_MAVEN_PATH_FILE $PROFILES_USERS_DIR/
sudo chmod +x $PROFILES_USERS_DIR/$JAVA_AND_MAVEN_PATH_FILE
source $PROFILES_USERS_DIR/$JAVA_AND_MAVEN_PATH_FILE

echo $JAVA_HOME | grep java
confirm_installation_step "STEP 1" "JAVA"

mvn -version | grep maven
confirm_installation_step "STEP 2" "MAVEN"
