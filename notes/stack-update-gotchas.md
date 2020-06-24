## Stack Updates to EC2 Instances: Info & Gotchas

The following are a collection of noteworthy points and caveats about EC2 Instances when stack updates apply.

1. #### What does and does not get changed when an EC2 instance undergoes a stack update?

   <u>QUESTION</u>: 

   > If I modify a resource and perform the corresponding stack update, will I always see the change reflected in my cloud environment?

   <u>ANSWER</u>: 

   > Not in all cases.

   This may seem confusing at first as to why, but an example probably most frequently encountered will help. Consider the following template:

   ```
   "Resources": {
     "MyMicroEC2": {
       "Type": "AWS::EC2::Instance",
       "Properties": {
         "SecurityGroups" : [ { "Ref" : "MyMicroSecurityGroup" } ],
         "UserData" : { "Fn::Base64" : { "Fn::Join" : [ "\n", [
           "#!/bin/bash",
           "",
           "# 1) Do some stuff, yum installs, etc...",
           "",
           "# 2) Implement all the metadata in AWS::CloudFormation::Init",
           "/opt/aws/bin/cfn-init -v --resource MyMicroEC2 ",
           { "Fn::Sub": "--region ${AWS::Region} --stack ${AWS::StackName}" },
           "",
           "# 3) Now that all initialization is done signal success",
           "/opt/aws/bin/cfn-signal -v --resource MyMicroEC2 ",
           { "Fn::Sub": "--region ${AWS::Region} --stack ${AWS::StackName}" }
         ]]}}},
       "Metadata": {
         "AWS::CloudFormation::Init": {
           "config": {
             "files": {
               "/etc/awslogs/awscli.conf": {
                 "content": { "Fn::Join" : [ "\n", [
                   "[plugins]",
                   "cwlogs = cwlogs",
                   "[default]",
                   { "Fn::Sub": "region = ${AWS::Region}" }
                 ]]}
                 ...
   ```

   If you were to perform the following steps:

   1. Modify the template to add another security group to SecurityGroups.
   2. Modify the template so that the content of awscli.conf has extra lines.
   3. Upload the modified template to its S3 bucket.
   4. Run a stack update off the modified template.

   You would find that...

   1. The EC2 instance now allows whatever new port traffic in that the new security group inbound rules specify, and the instance would now show the new security group in the online console.
   2. NO CHANGES would have been made to /etc/awslogs/awscli.conf.

   <u>EXPLANATION</u>: 
   Technically, the stack was updated with both changes. The EC2 instance now has a new security group and a new subset of metadata that instructs what to do when the EC2 instance is "initialized". Initialization is not something a stack update concerns itself with, only the metadata the initialization consumes when it happens. You still have to explicitly invoke those new metadata instructions - this is beyond the stack update itself.

   <u>REMEDY</u>:
   Part of defining the EC2 instance includes mechanisms for ensuring that it is modified in place whenever changes to the cloud formation stack on which it is based are made. EC2 instances that are based of the Amazon ECS-Optimized Amazon Linux AMI come with a library of python [helper scripts](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-helper-scripts-reference.html) in the bin directory that can be used, among other things, to perform and automate these updates.
   So, in order to get the awscli.conf file from the example refreshed after a stack update you have the following options:

   1. MANUALLY:
      Shell into the EC2 instance and call the [cfn-init](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-init.html) helper script
      *NOTE: Notice this is called once as part of EC2 creation as one of the last steps in the userdata block.*

   2. AUTOMATED:
      Use the [cfn-hup](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-hup.html) helper script.
      Add the following files for configuration:

      ```
      "/etc/cfn/cfn-hup.conf": {
        "mode": "000400",
        "owner": "root",
        "group": "root",
        "content" : { "Fn::Join" : [ "\n", [
          "[main]",
          { "Fn::Sub": "stack=${AWS::StackId}" },
          { "Fn::Sub": "region=${AWS::Region} " }
        ]]}
      },
      "/etc/cfn/hooks.d/cfn-auto-reloader.conf": {
        "content" : { "Fn::Join" : [ "\n", [
          "[cfn-auto-reloader-hook]",
          "triggers=post.update",
          "path=Resources.ECSLaunchConfiguration.Metadata.AWS::CloudFormation::Init",
          { "Fn::Sub" : "action=/opt/aws/bin/cfn-init -v --region ${AWS::Region} --stack ${AWS::StackName} --resource ECSLaunchConfiguration" }
        ]]}
      } ...
      ```

      Then make cfn-hup a service that polls the cloudformation "mothership" for updates to metadata.

      ```
      "services" : {
        "sysvinit" : {
          "cfn-hup" : {
            "enabled": "true",
            "ensureRunning" : "true",
            "files" : [
              "/etc/cfn/cfn-hup.conf",
              "/etc/cfn/hooks.d/cfn-auto-reloader.conf"
            ]
            ...
      ```
   A service means a daemon process, and this one uses cfn-hup at regular intervals. If cfn-hup determines an update was made to the stack against the resource in question, cfn-init is called.
          

2. #### What's the difference between Userdata and cfn-init?

   UserData is run only once upon creation of the ec2 instance and will call cfn-init for the first time as one of its last commands. Instead of being procedural like UserData, cfn-init is state-based in that it comprises only commands that deposit/replace files, set environment variables, update packages, etc. But the biggest difference is that cfn-init can be run again after the initial ec2 creation either by modifying anything in the AWS::CloudFormation::Init resource of the cfn stack template and performing a stack update, or shelling into the ec2 instance and running:

   ```
   /opt/aws/bin/cfn-init \
     -v --region ${AWS::Region} \
     --stack ${AWS::StackName} \
     --resource YourResourceName \
     --configsets ...
   ```

   If you make a modification to UserData cloudformation will REPLACE that EC2 instance during a stack update.
   If you make a modification to AWS::CloudFormation::Init, cloudformation will UPDATE that ec2 instance in place during a stack update. So, rule of thumb: Don't put anything in UserData that you want to be "refreshable" with a stack update
       

3. #### More on [Metadata](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/metadata-section-structure.html), [Initialization](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-init.html) and [Helper Scripts](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-helper-scripts-reference.html):
  
   You'll find a sufficient overview at the links provided above.
   but a few random definitions and points:
   
   - If your template calls the cfn-init script, the script looks for resource metadata rooted in the AWS::CloudFormation::Init metadata key.
   - The cfn-hup helper is a daemon that detects changes in resource metadata and runs user-specified actions when a change is detected. This allows you to make configuration updates on your running Amazon EC2 instances through the UpdateStack API action.
   - The user actions that the cfn-hup daemon calls periodically are defined in the hooks.conf configuration file. To support composition of several applications deploying change notification hooks, cfn-hup supports a directory named hooks.d that is located in the hooks configuration directory. You can place one or more additional hooks configuration files in the hooks.d directory. The additional hooks files must use the same layout as the hooks.conf file. 
   - services.sysvinit.servicename.files: A list of files. If cfn-init changes one directly via the files block, this service will be restarted.'
   - The cfn-init helper script processes these configuration sections and then services. If you require a different order, separate your sections into different config keys, and then use a configset that specifies the order in which the config keys should be processed.
   
   
   
   
