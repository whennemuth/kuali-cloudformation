

## Active choices plugin helper application

<img align="left" src="../jenkins1.png" alt="jenkins1" style="margin-right:15px;" />Many jenkins jobs use the [Active Choices Plugin](https://plugins.jenkins.io/uno-choice/) to add more dynamic behavior to fields in a job. With this plugin, field values/choices can be dynamically populated based on selections/entries in other fields. The code to drive this dynamic behavior would normally be entered by the job author as groovy scripting in special text areas of associated field(s). This can quickly become cumbersome and difficult to maintain as dynamic behavior increases in complexity. To solve this, the logic behind the dynamic behavior is moved out to an object-oriented java app running in a docker container that acts as a simple website that returns html for rendering in the job. The groovy scripting of any particular field is reduced down to an http call to this container over localhost providing its current value and that of all other fields in the job. The returned html is used to re-render a single field (*html fragment)* or many fields at once.

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

1. #### Clone this repository:

   ```
   git clone https://github.com/bu-ist/kuali-infrastructure.git
   cd kuali-infrastructure/kuali_jenkins/KualiUI
   ```

      

2. ------

   #### Test in local development environment:

   The application is a basic web server that populates its html responses from lookups to the aws account using a java aws api library.
   There are 2 basic request scenarios:

   1. **Simple field:**
      In this scenario, you would be making an http request to obtain the html for a single field in the jenkins job.
      A class central to this scenario is `org.bu.jenkins.EntryPoint`. The following example will launch a new browser screen that renders a tabular view of all the cloudformation stacks created for kuali-research *(assumes eclipse IDE)*:
      - **Main class:** `"org.bu.jenkins.EntryPoint"`
      - **Arguments:**
        profile=[your aws profile]
        parameter-name=stack
        logging_level=debug
        browser=true
        keep-running=true
        *(SEE: [Amazon documentation for profiles](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html) - your profile should be connected to an IAM role that, at a minimum, allows you to list cloudformation entities)*
      - **JRE:** "Project execution environment"
      - **Dependencies:**
        - Classpath Entries: "JRE System Library"
        - Classpath Entries: [Current Project]
        - Classpath Entries: "Maven Dependencies"
      - **Source:** "Default"
      - **Environment:**
   2. **Compound field:**
      In this scenario, you would be making an http request to obtain the html for a group of fields in the jenkins job. You are still dealing with one active choices job field, but the html that is returned for it to render comprises a group of nested fields. Typically you might place an entire job in one active choices field. One such field is used in the jenkins job for creating the cloudformation stack for an entire kuali landscape. To render a mock representation of this job in your browser over localhost, run the following debug configuration *(assumes eclipse IDE)*:
      - **Main class:** 
        - Mocked: A mock entry is placed in the html table of existing stacks as part of the output.
          `"org.bu.jenkins.job.kuali.StackCreateDeleteTest"`
        - Unmocked: The html table of existing stacks will be empty.
          `"org.bu.jenkins.mvc.controller.kuali.job.StackCreateDeleteController"`
      - **Arguments:**
        profile=[your aws profile]
        logging_level=debug
        *(SEE: [Amazon documentation for profiles](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html) your profile should be connected to an IAM role that is permissive enough to query the different aws resources involved)*
      - **JRE:** "Project execution environment"
      - **Dependencies:**
        - Classpath Entries: "JRE System Library"
        - Classpath Entries: [Current Project]
        - Classpath Entries: "Maven Dependencies"
      - **Source:** "Default"
      - **Environment:** "logging_level=DEBUG"

3. ------

   #### Build, push, and deploy:

   - Build:
     To build the app into a docker image.

     ```
     sh docker.sh build
     ```

     The image name will be `"kuali-jenkins-http-server"`
     To change the logging level of the app:

     ```
     sh docker.sh logging_level=debug
     ```

   - **Push:**

     - **Elastic Container Registry:**

       This will be the default push target. Only a profile is needed to identify the account and one that has a sufficient role to push.

       ```
       sh docker.sh push profile=[my profile]
       ```

     - **Dockerhub:**
       Provide a user and password for the dockerhub account

       ```
       sh docker.sh push user=[dockerhub user] password=[dockerhub password]
       ```

       or to be prompted for the password:

       ```
       sh docker.sh push user=[dockerhub user]
       ```

   - **Deploy:**
     A [Systems Manager send command](https://docs.aws.amazon.com/cli/latest/reference/ssm/send-command.html) is issued to any ec2 instance identified as a kuali jenkins server. The command instructs the instance to refresh its docker image from the registry and restart its containers. 

     ```
     sh docker.sh deploy profile=[my profile]
     ```

   - **All-in-one:**
     Omit any of the terms "build", "push", or "deploy" and it is assumed that you want each of them performed in order. Use any of the parameters already covered.


     EXAMPLES:

     - Accept all defaults (ECR, "INFO" logging level)

       ```
       sh docker.sh profile=[my profile]
       ```

     - Use dockerhub and up the logging level:

       ```
       sh docker.sh user=[dockerhub user] password=[dockerhub password] logging_level=debug
       ```

       

