# What is  smtpsweeper? #

This is a proof of concept program that demonstrates how to utilize /dev/tcp with bash.
This tool can test smtp VRFY and EXPN commands against poorly configured smtp servers. You can send specific accounts to check, or send a wordlist to be done in parallel.
See usage for more details on how to use it.



# LAB SETUP  #

vm setup: https://linuxhint.com/install_ubuntu_vmware_workstation/
install net-tools

docker setup: https://fabianlee.org/2019/09/28/docker-installing-docker-ce-on-ubuntu-bionic-18-04/

mail setup: https://fabianlee.org/2019/10/23/docker-running-a-postfix-container-for-testing-mail-during-development/

1. get a shell
docker container exec -it mail /bin/bash


2. edit /etc/postfix/main.cf to disable helo required and enable vrfy

sed -i -e 's/disable_vrfy_command = no/disable_vrfy_command = yes/g' /etc/postfix/main.cf
sed -i -e 's/smtpd_helo_required = yes/smtpd_helo_required = no/g' /etc/postfix/main.cf
 
3. edit /etc/postfix/master.cf to remove rate limits

sed -i -e 's/-o smtpd_soft_error_limit=1001//g' -e 's/-o smtpd_hard_error_limit=1000//g' /etc/postfix/master.cf

echo "  -o smtpd_soft_error_limit=99999" >> /etc/postfix/master.cf
echo "  -o smtpd_hard_error_limit=9999999" >> /etc/postfix/master.cf
echo "  -o smtpd_junk_command_limit=9999999" >> /etc/postfix/master.cf
4. load changes
postfix reload

5. add entry to hosts
echo "127.0.0.1         domain.com" >> /etc/hosts
5. exit shell
