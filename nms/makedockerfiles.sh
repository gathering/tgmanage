#!/bin/sh
awk -v TARGET=/dev/null '
BEGIN {
    system("mkdir -p build")
}
/^@template/ {
    TARGET="build/Dockerfile."$2;
    TARGETS[ntargets++]=$2;
    print "# Generated" > TARGET
    next;
}
{
    print > TARGET
}
END {
    print "#! /bin/sh" > "build/build.sh"
    print "set -e" > "build/build.sh"
    for (x in TARGETS) {
        a = TARGETS[x]
        print "echo Building "a > "build/build.sh"
        print "echo Logs: build/"a".log" > "build/build.sh"
        print "docker build -t "a" -f build/Dockerfile."a" . > build/"a".log 2>&1 || cat build/"a".log" > "build/build.sh"
    }
    system("chmod +x build/build.sh")
}' < Dockerfile.in
build/build.sh
