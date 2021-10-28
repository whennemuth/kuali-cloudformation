## Connect to the RDS instance (from your computer)

So, the Kuali RDS instances are up and running and the jump server has been created (both as part of the main stack creation).
And now you want to connect to the RDS instance from your computer (as with a database client like mysql workbench or SQL Developer).

#### Main obstacle:

In the past, connecting to databases in private subnets is done through a bastion or jump server.

Overall, database access for kuali is secure and fairly well isolated from everything outside of its [vpc](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html).
The traditional approach for connecting to the database in a private subnet works when you have access to the jump box.
For Kuali, this can be the case if the jumpbox is placed in the campus subnets because those subnets have transit gateway attachments that connect them to internal BU networks. Therefore you can access the jumpbox directly if you are logged into the BU vpn.
However, that won't work in this case because the following are true:

- The jump server resides in the same private subnet as the RDS instance/cluster.
  This distinguishes it from a bastion server, better to refer to it as a "jump box".
  This also brings the same level of isolation to the jump server as for the database instances themselves *(but there's still a way in - see solution below)*.
- The RDS instance(s) have endpoints that are not publicly accessible.
- The jump server has only a private ip address.
- The private subnet has only a route to a NAT gateway, so no ingress can be initiated to either the database or the jumpbox instances from outside of the vpc.
- The security group for the jump server allows ingress over only one port (1521) and only for traffic originating from either of the two private database subnets.
- The security group for the database instances allows ingress over only one port (1521) and only for traffic originating from either of the two private subnets or either of the two campus subnets (where the application servers reside).

This increases security because the jump server has no SSH port open, no SSH keys to maintain, and no direct ingress from outside the vpc possible.

However, with the jump box locked down in this way the challenge becomes how to get to it.
Aren't we defeating the purpose of the jump box if we can't reach it?    

#### Solution:

Traditionally, it's mattered ***where*** you are in network terms (VPN, subnet, gateways, etc.) or what keys you have when it comes to access to resources like servers and databases. However, AWS promotes moving special access away from putting up doorways and locks in infrastructure, "wall up" those doorways, and instead focus more on role-granted use of services that open doorways for you. Then it mostly matters ***who*** you are. Putting IAM and services more at the center of this has many convenience and security benefits, as explained [here](https://aws.amazon.com/blogs/compute/new-using-amazon-ec2-instance-connect-for-ssh-access-to-your-ec2-instances/) and [here](https://medium.com/@dnorth98/hello-aws-session-manager-farewell-ssh-7fdfa4134696).

Security would still be adequate if our jump box were moved to one of the campus subnets, giving access over ssh directly through our VPN.
However, the jump box has a role that allows access through [ssm](https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html). For instance, if all you wanted to do was shell into it and poke around, you'd do that like this:

   ```
aws ssm start-session --target [instance-id of jump server]
   ```

We'd like this same kind of access to RDS instances.
But, you cannot use a start-session command directly against the RDS instance itself due to the `--target` parameter requiring an ec2 instance id, which an RDS instance does not have. Hence the jump box.
This is because the target of an ssm tunneling session requires it have installed client software that allows it to participate in the session. An RDS instance does not have an operating system per se, and is not something you can load client software on to - hence the jumpbox proxying.

The solution makes modified use of the `ssm start-session` command.
You execute this same command to get to the jumbox, but you use the session to tunnel SSH through to the RDS instance. 
The ssh command includes parameters to set up the jump box up as a forwarder (proxy) for stdin and stdout from you computer over a port you designate to the rds instance.

But again, the jump box is in the private subnet with no ports to anything but the database itself, so how is this ssh connection possible?
This is handled as follows *(See: [Set up EC2 Instance Connect](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-connect-set-up.html))*:

   - The jump server has [EC2 Instance Connect](https://aws.amazon.com/blogs/compute/new-using-amazon-ec2-instance-connect-for-ssh-access-to-your-ec2-instances/) installed on it.
   - You use the cli `ec2-instance-connect send-ssh-public-key` method to drop a one-time public key on the jump server.
   - Use an ssh client (like OpenSSH) to connect to the jump box.

You are now using an ssh client, but IAM policies and principals control SSH access.

This makes for a series of commands, but for which there is a helper script.
The helper script follows the approach from these references:

   - [Secure RDS Access through SSH over AWS SSM](https://codelabs.transcend.io/codelabs/aws-ssh-ssm-rds/index.html#6)
   - [Enable SSH connections through Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html) 

   **Helper script usage:****

   ```
# Example:
git clone https://github.com/bu-ist/kuali-infrastructure.git
cd kuali-infrastructure/kuali_rds/jumpbox
sh tunnel.sh profile=[your.profile] landscape=ci

# Or, if you are running into bash version incompatibilities, you can run the dockerized image for this repo...

source <(docker run --rm -v $HOME/.aws:/root/.aws bostonuniversity/kuali-infrastructure tunnel landscape=ci) ssm
   ```

   The helper script executes something like this:

   ```
echo -e 'y\n' | ssh-keygen -t rsa -f tempkey -N '' >/dev/null 2>&1
   
aws ec2-instance-connect send-ssh-public-key \
  --instance-id i-0f7eaa9c36919fa26 \
  --availability-zone us-east-1c \
  --instance-os-user ec2-user \
  --ssh-public-key file://./tempkey.pub
   
ssh -i tempkey \
  -Nf -M \
  -S temp-ssh.sock \
  -L 5432:kuali-oracle-sb.clb9d4mkglfd.us-east-1.rds.amazonaws.com:1521 \
  -o "UserKnownHostsFile=/dev/null" \
  -o "ServerAliveInterval 10" \
  -o "StrictHostKeyChecking=no" \
  -o ProxyCommand="aws ssm start-session --target i-0f7eaa9c36919fa26 --document AWS-StartSSHSession --parameters portNumber=%p --region=us-east-1" \
  ec2-user@i-0f7eaa9c36919fa26
   ```
