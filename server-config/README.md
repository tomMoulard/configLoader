# Server configuration

## Goal
```bash
$ docker-compose up -d
```

Now you have my own server configuration

## Configuration
Don't forget to change db passwords. (migth not be needed since they are beyond
the reverse proxy).
Configuration files are: `docker-compose.yml`, `nginx.conf`

## TODO
 - [ ] nginx.conf
 - [ ] next cloud configuration file
 - [ ] reverse proxy with ssl and NAT/PAT

| Status | Address | port(s)|
|:--:|--|--|
| [ ] | gitlab.tom.moulard.org | 22, 80, 443 |
| [ ] | cloud.tom.moulard.org | 80, 443 |
| [ ] | tom.moulard.org | 80, 443 |