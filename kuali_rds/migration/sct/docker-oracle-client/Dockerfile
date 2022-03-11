# References:
#   https://oracle-base.com/articles/misc/oracle-instant-client-installation
#   https://docs.oracle.com/cd/B28359_01/server.111/b31189/apd.htm

FROM centos

# Install sqlplus client
RUN \
  dnf -y --disablerepo '*' --enablerepo=extras swap centos-linux-repos centos-stream-repos && \
  dnf -y distro-sync && \
  cd /etc/yum.repos.d && \
  rm -f public-yum-ol7.repo && \
  curl https://yum.oracle.com/public-yum-ol7.repo -o public-yum-ol7.repo && \
  yum install -y yum-utils && \
  yum install -y libaio.x86_64 glibc.x86_64 && \
  dnf install -y libnsl && \
  yum-config-manager --enable ol7_oracle_instantclient && \
  printf "\n\nTHE FOLLOWING PACKAGES ARE AVAILABLE:\n" && \
  yum list oracle-instantclient* && \
  yum install -y --nogpgcheck \
    oracle-instantclient18.3-basic \
    oracle-instantclient18.3-sqlplus \
    oracle-instantclient18.3-tools

# Install aws cli and session manager
RUN \
  yum install -y unzip && \
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
  unzip awscliv2.zip && \
  ./aws/install && \
  curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm" && \
  yum install -y session-manager-plugin.rpm && \
  yum -y install openssh-server openssh-clients

RUN dnf install -y dos2unix && \
  yum install -y jq

WORKDIR /usr/local/sbin/

COPY docker/bash/*.sh /usr/local/sbin/
COPY docker/sql/*.sql /usr/local/sbin/

RUN \
  dos2unix /usr/local/sbin/* && \
  chmod -R +x /usr/local/sbin/
  

ENV CLIENT_HOME=/usr/lib/oracle/18.3/client64
ENV ORACLE_HOME=$CLIENT_HOME
ENV LD_LIBRARY_PATH=$CLIENT_HOME/lib
ENV PATH=$PATH:$CLIENT_HOME/bin
ENV TNS_ADMIN=$CLIENT_HOME/network/admin
ENV ORACLE_SID=ORCLCDB
ENV AWS_REGION=us-east-1

ENTRYPOINT ["/usr/local/sbin/startup.sh"]


