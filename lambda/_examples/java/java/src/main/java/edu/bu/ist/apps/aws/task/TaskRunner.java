package edu.bu.ist.apps.aws.task;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.json.JSONArray;
import org.json.JSONObject;

import edu.bu.ist.apps.aws.lambda.Logger;
import edu.bu.ist.apps.aws.task.s3.S3File;
import edu.bu.ist.apps.aws.task.s3.S3FileParms;

/**
 * A TaskRunner identifies and runs a single task.
 * For example if the lambda function were invoking this java application, it would be passing in a "task"
 * parameter to identify what function it is to perform. That task value is inspected here and the corresponding
 * functionality is executed and TaskResult returned.
 * 
 * @author wrh
 *
 */
public class TaskRunner {
	
	public TaskResult run(Task task, Object resourceProperties) throws Exception {
		return run(task, resourceProperties, null);
	}
	
	public TaskResult run(Task task, Object resourceProperties, Logger logger) throws Exception {
		TaskResult result = null;
		String maskJson = null;
		final OutputMask outputmask;
		
		switch(task) {
			case CONTAINER_ENV_VARS:
				/**
				 * There is a properties file sitting in an S3 bucket that contains the environment variables to 
				 * pass to docker run command for container. Go get that file.
				 */
				S3File s3file = getS3FileResult(resourceProperties, logger);
				maskJson = extractValue(resourceProperties, "outputmask", logger);
				outputmask = OutputMask.getInstance(maskJson, logger);
				result = TaskResult.getInstanceFromProperties(s3file.getBytes(), outputmask);				
				break;
			case EC2_PUBLIC_KEYS:
				// TODO: The limit to a CustomResource response is 4k. Each public key is at least 2K.
				// Therefore need to call this one at a time for each key from the cloudformation template.
				// OR better yet, do this:
				// https://aws.amazon.com/blogs/devops/authenticated-file-downloads-with-cloudformation/
				/**
				 * There are a number of public rsa keys files sitting in an s3 bucket. Get each by name and
				 * create a TaskResult that houses them all, indexed by their provided user names.
				 */				
				List<TaskResult> results = new ArrayList<TaskResult>();
				maskJson = extractValue(resourceProperties, "outputmask", logger);
				outputmask = OutputMask.getInstance(maskJson, logger);
				String s3FileJson = extractValue(resourceProperties, "s3files", logger);
				JSONArray keysinfo = new JSONObject(s3FileJson).getJSONArray("s3keyfiles");
				
				// Get each s3file as its own TaskResult and merge them into a single TaskResult
				keysinfo.forEach( (keyinfo) -> {
					String username = ((JSONObject) keyinfo).getString("user");
					String keyfile = ((JSONObject) keyinfo).getString("keyfile");
					try {							
						S3File downloaded = getS3FileResult(resourceProperties, keyfile, logger);
						TaskResult tempResult = TaskResult.getInstanceFromBlob(downloaded.getBytes(), outputmask);
						tempResult.replaceKey("blob", username);
						results.add(tempResult);
					} 
					catch (Exception e) {
						throw new RuntimeException(e);
					}
				});
				
				result = TaskResult.getMergedInstance(results, outputmask);
				break;
			case UNKNOWN:
				
				break;
		}
		
		return result;
	}
	
	private S3File getS3FileResult(Object resourceProperties, Logger logger) throws Exception {
		return getS3FileResult(resourceProperties, null, logger);
	}
		
	private S3File getS3FileResult(Object resourceProperties, String s3filename, Logger logger) throws Exception {
		/**
		 *  Get all possible expected parameters from the resourceProperties object.
		 *  NOTE: 
		 *    profile or accessKey/secretKey can be null when this function is
		 *    called as part of a cloud formation lambda-backed CustomResource.
		 *    This means that the lambda SecurityToken passed to the lambda function
		 *    gives it the role it needs without authentication required. Technically,
		 *    authentication was performed the minute one logs into the AWS management
		 *    console and cloud-formation inherits the right to assign this role to
		 *    the token from the IAM credentials of the person who logged in (ostensibly an admin).
		 *  
		 *    If running this locally, or through the AWS cli, you would need to specify
		 *    these IAM credentials (profile or accessKey/secretKey)
		 */
		String region = extractValue(resourceProperties, "region", logger);
		String s3bucket = extractValue(resourceProperties, "s3bucket", logger);
		if(s3filename == null) {
			s3filename = extractValue(resourceProperties, "s3file", logger);
		}
		String profile = extractValue(resourceProperties, "profile", logger); // Needed if running locally.
		String accessKey = extractValue(resourceProperties, "accesskey", logger); // Needed if running locally.
		String secretKey = extractValue(resourceProperties, "secretkey", logger); // Needed if running locally.
		
		// profile and accessKey/secretKey can be null if running as part of a cloud-formation execution.
		S3File s3file = new S3File(new S3FileParms()
				.setRegion(region)
				.setBucketname(s3bucket)
				.setFilename(s3filename)
				.setLogger(logger)
				.setProfilename(profile)
				.setAccessKey(accessKey)
				.setSecretKey(secretKey));
		
		return s3file;
	}
	
	private String extractValue(Object resourceProperties, String name, Logger logger) {
		return new TaskFactory().extractValue(resourceProperties, name, logger);
	}
	
	public static void main(String[] args) throws Exception {
		
		// 1) Run a task that gets and loads a properties file
		Map<String, Object> resourceProperties = new LinkedHashMap<String, Object>();
		resourceProperties.put("task", Task.CONTAINER_ENV_VARS.getShortname());
		resourceProperties.put("region", "us-east-1");
		resourceProperties.put("s3bucket", "kuali-conf");
		resourceProperties.put("s3file", "qa/core/environment.variables.s3.env");
		resourceProperties.put("outputmask", "{"
				+ "class: edu.bu.ist.apps.aws.task.BasicOutputMask, "
				+ "parameters: { "
				+ "  fieldsToMask: { "
				+ "    full: [], "
				+ "    logs: [AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, MONGO_PASS, SERVICE_SECRET_1]"
				+ "  }"
				+ "}}");
		resourceProperties.put("profile", "ecr.access");
		
		Logger logger = (String msg) -> { System.out.println(msg); };		
		TaskRunner runner = new TaskRunner();		
		TaskResult result = runner.run(Task.CONTAINER_ENV_VARS, resourceProperties, logger);		
		System.out.println(result);		
		
		
		// 2) Run a task that gets 3 public ssh keys at once.
		resourceProperties.remove("s3file");
		resourceProperties.put("s3files", 
				"{s3keyfiles: ["
				+ "  {user:wrh, keyfile:\"ecs/ssh-keys/rsa-key-wrh\"},"
				+ "  {user:mukadder, keyfile:\"ecs/ssh-keys/rsa-key-mukadder\"},"
				+ "  {user:dhaywood, keyfile:\"ecs/ssh-keys/rsa-key-dhaywood\"}"
				+ "]}");
		resourceProperties.put("outputmask", "{"
				+ "class: edu.bu.ist.apps.aws.task.BasicOutputMask, "
				+ "parameters: { "
				+ "  fieldsToMask: { "
				+ "    full: [], "
				+ "    logs: [wrh, mukadder, dhaywood]"
				+ "  }"
				+ "}}");
		result = runner.run(Task.EC2_PUBLIC_KEYS, resourceProperties, logger);		
		System.out.println(result);				
	}
}
