#!/bin/bash
apt-get update -y
apt-get install -y python3-pip
pip3 install flask gunicorn
mkdir -p /opt/ecobuy
cat > /opt/ecobuy/app.py <<'PYEOF'
__APP_PY__
PYEOF
cat > /etc/systemd/system/ecobuy.service <<'SVC'
[Unit]
Description=EcoBuy app
After=network.target
[Service]
WorkingDirectory=/opt/ecobuy
ExecStart=/usr/local/bin/gunicorn -w 2 -b 0.0.0.0:80 --access-logfile - --error-logfile - --log-syslog --log-syslog-facility local0 app:app
Restart=always
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload
systemctl enable --now ecobuy
