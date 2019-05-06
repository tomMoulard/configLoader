# Server configuration

## Goal
```bash
$ docker-compose up -d
```

Now you have my own server configuration

## Configuration
Don't forget to change db passwords. (migth not be needed since they are beyond
the reverse proxy).
Fill vpn secrets(if none provided, they are generated directly).
Configuration files are: `docker-compose.yml`, `nginx.conf`

## TODO
### New ideas
 - [X] traefik
 - [X] gitlab
 - [X] nextcloud
 - [X] nginx
 - [X] weechat
 - [X] transmission
 - [X] vpn
 - [X] jupyter
 - [X] pastebin
 - [ ] readthedoc
 - [X] pastebin
 - [ ] image hosting
 - [ ] [hackmd](https://github.com/hackmdio/docker-hackmd)
 - [ ] jekyll

### List
 - [ ] which database ? maria / mysql / mongo / postgres
 - [X] nginx.conf
 - [ ] next cloud configuration file
 - [ ] create a git repository auto in gitlab for // FIXME
 - [ ] Create a Dockerfile for a mail server
 - [ ] reverse proxy with ssl and NAT/PAT
 - [ ] Testing
    - [ ] traefik
    - [ ] gitlab
    - [ ] nextcloud
    - [X] nginx
    - [ ] weechat
    - [X] transmission
    - [X] vpn
    - [ ] jupyter
    - [X] pastebin
    - [ ] jekyll

## Configuration
| Status | Address | port(s)|
|:--:|--|--|
| [ ] | gitlab.tom.moulard.org | 22, 80, 443 |
| [ ] | cloud.tom.moulard.org | 80, 443 |
| [ ] | tom.moulard.org | 80, 443 |
| [ ] | mail.tom.moulard.org | 25(recv mail), 465(ssl), 587(TLS), 143(IMAP), 993(IMAP), 110(POP3), 995(POP3) |
| [ ] | torrent.tom.moulard.org | 80, 443 (redirect 80 to 443) |
| [ ] | vpn.tom.moulard.org | 500, 4500 |
| [ ] | jupiter.tom.moulard.org | 80, 443 (redirect 80 to 443) |
| [ ] | paste.tom.moulard.org | 80, 443 (redirect 80 to 443) |

## Installation
### Nginx
Configuration file to put in `$HOME/srv/nginx/nginx.conf`
```
server {
    root /etc/nginx/conf.d/www;
    index index.html;

    location /{
        try_files $uri $uri/ =404;
        autoindex on;
    }
}
```

And put your files in the folder `$HOME/srv/nginx/www`.