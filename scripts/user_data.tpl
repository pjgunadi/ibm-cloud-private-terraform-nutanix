#cloud-config
hostname: ${vmname}
password: ${password}
chpasswd: { expire: False }
ssh_pwauth: True
timezone: ${timezone}