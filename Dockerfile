FROM ubuntu:18.04

RUN apt-get update && apt upgrade -y
RUN apt install -y git
RUN apt install -y vim
RUN apt install -y tree
RUN apt install -y curl
RUN apt install -y make

CMD [ "/bin/bash" ]
