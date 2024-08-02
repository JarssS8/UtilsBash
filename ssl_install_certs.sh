 #!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
CHECK_MARK="\xE2\x9C\x94"
CROSS_MARK="\xE2\x9D\x8C"

# Check if InstallCert.java exists
if [ ! -f InstallCert.java ]; then
    echo "${RED}${CROSS_MARK} InstallCert.java does not exist ${NC}"
    exit 1
else
    echo "${GREEN}${CHECK_MARK} InstallCert.java exists ${NC}"
fi

 # Check if InstallCert.class and InstallCert$SavingTrustManager.class exist
if [ ! -f InstallCert.class ] || [ ! -f InstallCert\$SavingTrustManager.class ]; then
    echo "${RED}${CROSS_MARK} InstallCert.java is not compiled ${NC}"
    javac InstallCert.java
    if [ $? -ne 0 ]; then
        echo "${RED}${CROSS_MARK} Compilation failed ${NC}"
        exit 1
    fi
    echo "${GREEN}${CHECK_MARK} Compilation successful ${NC}"
else
    echo "${GREEN}${CHECK_MARK} InstallCert.java is compiled ${NC}"
fi

# Check if use asdf 
if [ ! -d ~/.asdf ]; then
    echo "${RED}${CROSS_MARK} asdf is not installed ${NC}"
    exit 1
fi

# Check current java version with asdf current
CURRENT_JAVA_VERSION=$(asdf current | grep 'java' | awk '{print $1}')
CURRENT_JDK_VERSION=$(asdf current | grep 'java' | awk '{print $2}')
if [ -z "$CURRENT_JAVA_VERSION" ]; then
    echo "${RED}${CROSS_MARK} No java version is set ${NC}"
    exit 1
else
    echo "${GREEN}${CHECK_MARK} Current java version is set ${CURRENT_JAVA_VERSION}/${CURRENT_JDK_VERSION} ${NC}"
fi

#Check if instalation exists
if [ ! -d ~/.asdf/installs/$CURRENT_JAVA_VERSION/$CURRENT_JDK_VERSION ]; then
    echo "${RED}${CROSS_MARK} Java version $CURRENT_JDK_VERSION is not installed ${NC}"
    exit 1
else
    echo "${GREEN}${CHECK_MARK} Java version $CURRENT_JDK_VERSION is installed ${NC}"
fi

PATH_TO_JAVA=~/.asdf/installs/$CURRENT_JAVA_VERSION/$CURRENT_JDK_VERSION/lib/security

java InstallCert $1
if [ $? -ne 0 ]; then
    echo "${RED}${CROSS_MARK} Certificate download failed ${NC}"
    exit 1
fi
if [ ! -f jssecacerts ]; then
    echo "${RED}${CROSS_MARK} Certificate file does not exist ${NC}"
    exit 1
fi
mv jssecacerts $PATH_TO_JAVA
if [ $? -ne 0 ]; then
    echo "${RED}${CROSS_MARK} Move certificate failed ${NC}"
    exit 1
fi
echo "${GREEN}${CHECK_MARK} Move certificate successful ${NC}"
echo "${GREEN}${CHECK_MARK} Certificate moved to $PATH_TO_JAVA ${NC}"



