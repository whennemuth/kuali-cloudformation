package edu.bu.ist.apps.aws.task;

/**
 * Definitions for each task that the CustomResourceHandler could perform and utilities for
 * extracting a task identifier out of a map and validating it can be matched up to one of the enum values.
 * 
 * @author wrh
 *
 */
public enum Task {
	
	CONTAINER_ENV_VARS("get.container.env.vars",
			"Get environment variables stored in properties file "
			+ "in S3 bucket used for docker container run command"), 
	
	EC2_PUBLIC_KEYS("get.ec2.public.keys",
			"Get the public rsa keys stored in S3 bucket so user "
			+ "data script in EC2 creation can place them in the appropriate home folders"),
	
	UNKNOWN("unknown.task",
			"The string used to identify the task matches no known task");
	
	private String shortname;
	private String description;
	
	private Task(String shortname, String description) {
		this.shortname = shortname;
		this.description = description;
	}
		
	public String getDescription() {
		return description;
	}	
	
	public String getShortname() {
		return shortname;
	}
}
