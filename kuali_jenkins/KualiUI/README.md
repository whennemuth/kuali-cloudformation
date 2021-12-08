## Active choices plugin helper application

<img align="left" src="../jenkins1.png" alt="jenkins1" style="margin-right:15px;" />Many jenkins jobs use the [Active Choices Plugin](https://plugins.jenkins.io/uno-choice/) to add more dynamic behavior to fields in a job. With this plugin, field values/choices can be dynamically populated based on selections/entries in other fields. The code to drive this dynamic behavior must be entered by the job author as groovy scripting in special text areas connected to the associated field(s). This can quickly become cumbersome and difficult to maintain as dynamic behavior increases in complexity. To solve this, the logic behind the dynamic behavior is moved out into a docker container that acts as a simple website that returns html for rendering in the job. The groovy scripting of each job field is reduced down to an http call to this container over localhost providing its current value and all other field values. The returned html is used to re-render a single field (*html fragment)* or many fields at once.

### Prerequisites:

- **Java IDE *[optional]*:**
  This application is written in java. Use a java-based development environment to make changes/extentions to it, like [Eclipse](https://www.eclipse.org/downloads/)
  
- **Maven *[optional]*:**
  [Maven](https://maven.apache.org/download.cgi) is used as the building and package manager for the application. You will need it to run and test the app locally *(not as a docker container).*
  
- **Docker:**
  This application runs in a docker container. Installation steps vary depending on operating system. For linux:

  ```
  sudo curl -fsSL https://get.docker.com/ | sh
  usermod -aG docker [your username] (adds your username to the docker group)
  ```

- **AWS CLI:** 
  If you don't have the AWS command-line interface, you can download it here:
  [https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
  
- **IAM User/Role:**
  The cli needs to be configured with the [access key ID and secret access key](https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html#access-keys-and-secret-access-keys) of an (your) IAM user. This user needs to have a role with policies sufficient to cover all of the actions to be carried out (stack creation, VPC/subnet read access, ssm sessions, secrets manager read/write access, etc.). Preferably your user will have an admin role and all policies will be covered.
  
- **Bash:**
  You will need the ability to run bash scripts. Natively, you can do this on a mac, though there may be some minor syntax/version differences that will prevent the scripts from working correctly. In that event, or if running windows, you can either:
  - Clone the repo on a linux box (ie: an ec2 instance), install the other prerequisites and run there.
  - Download [gitbash](https://git-scm.com/downloads)

### Steps:

Build the application into a docker image and deploy to a docker registry: