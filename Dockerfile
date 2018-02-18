FROM alpine:latest

ENV ANSI_COLORS_DISABLED=1

RUN apk --update add git perl curl wget make gcc ncurses \
                     perl-dev musl-dev openssl openssl-dev; \
    curl https://cpanmin.us > /usr/local/bin/cpanm && \
    chmod 755 /usr/local/bin/cpanm; \
    mkdir -p /opt/bugzilla/repo/bmo

COPY . /opt/bmo-admin-scripts
WORKDIR /opt/bmo-admin-scripts
RUN cpanm --notest --installdeps .

CMD /opt/bmo-admin-scripts/push-text 2>/dev/null
