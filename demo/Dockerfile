FROM ubuntu:20.04

WORKDIR /root/workspace/configLoader/

RUN apt-get update && apt upgrade -y
RUN apt install -y git
RUN apt install -y vim
RUN apt install -y tree
RUN apt install -y curl
RUN apt install -y make
RUN apt install -y wget

ADD ./entrypoint.sh /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
