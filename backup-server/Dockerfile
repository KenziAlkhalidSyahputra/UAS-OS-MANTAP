FROM alpine:3.20

RUN apk add --no-cache openssh-server \
 && adduser -D -s /bin/sh backupuser \
 && echo "backupuser:$(cat /proc/sys/kernel/random/uuid)" | chpasswd \
 && mkdir -p /home/backupuser/.ssh /home/backupuser/incoming \
 && chown -R backupuser:backupuser /home/backupuser \
 && chmod 700 /home/backupuser/.ssh \
 && printf '%s\n' \
      'PasswordAuthentication no' \
      'KbdInteractiveAuthentication no' \
      'PubkeyAuthentication yes' \
      'PermitRootLogin no' \
      'AllowUsers backupuser' \
      'AllowTcpForwarding no' \
      'X11Forwarding no' \
    >> /etc/ssh/sshd_config

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
