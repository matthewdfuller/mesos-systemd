#!/bin/bash -x

if [ "$(etcdctl get /bootstrap.service/images-base-bootstrapped)" == "true" ]; then
    echo "base images already bootstrapped, skipping"
    exit 0
fi
etcdctl set /bootstrap.service/images-base-bootstrapped true

etcdctl set /images/awscli   	"index.docker.io/behance/awscli:latest"

# pull down images serially to avoid a FS layer clobbering bug in docker 1.6.x
docker pull index.docker.io/behance/docker-gocron-logrotate
docker pull index.docker.io/behance/docker-sumologic:latest
docker pull index.docker.io/behance/docker-sumologic:syslog-latest
docker pull index.docker.io/behance/docker-dd-agent
docker pull $(etcdctl get /images/awscli)