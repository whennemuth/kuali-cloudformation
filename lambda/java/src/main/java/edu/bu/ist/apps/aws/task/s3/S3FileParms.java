package edu.bu.ist.apps.aws.task.s3;

import java.util.LinkedHashMap;
import java.util.Map;

import com.amazonaws.auth.AWSStaticCredentialsProvider;
import com.amazonaws.auth.BasicAWSCredentials;
import com.amazonaws.auth.profile.ProfileCredentialsProvider;
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.AmazonS3ClientBuilder;

import edu.bu.ist.apps.aws.lambda.Logger;

/**
 * Just a bean for S3File parameters and enforcing their requirements.
 * 
 * @author wrh
 *
 */
public class S3FileParms {
	private enum parmname {
		region, bucketname, filename, profilename, accessKey, secretKey, logger;
	}
	private Map<parmname, Object> parms = new LinkedHashMap<parmname, Object>();
	
	private StringBuilder issue = new StringBuilder();
	
	public String getRegion() {
		return getStringParm(parmname.region);
	}
	public S3FileParms setRegion(String region) {
		return setParm(parmname.region, region);
	}
	public String getBucketname() {
		return getStringParm(parmname.bucketname);
	}
	public S3FileParms setBucketname(String bucketname) {
		return setParm(parmname.bucketname, bucketname);
	}
	public String getFilename() {
		return getStringParm(parmname.filename);
	}
	public S3FileParms setFilename(String filename) {
		return setParm(parmname.filename, filename);
	}
	public String getProfilename() {
		return getStringParm(parmname.profilename);
	}
	public S3FileParms setProfilename(String profilename) {
		return setParm(parmname.profilename, profilename);
	}
	public String getAccessKey() {
		return getStringParm(parmname.accessKey);
	}
	public S3FileParms setAccessKey(String accessKey) {
		return setParm(parmname.accessKey, accessKey);
	}
	public String getSecretKey() {
		return getStringParm(parmname.secretKey);
	}
	public S3FileParms setSecretKey(String secretKey) {
		return setParm(parmname.secretKey, secretKey);
	}	
	public Logger getLogger() {
		return (Logger) parms.get(parmname.logger);
	}
	public boolean hasLogger() {
		return getLogger() != null;
	}
	public S3FileParms setLogger(Logger logger) {
		return setParm(parmname.logger, logger);
	}
	private S3FileParms setParm(parmname parmname, Object newparm) {		
		try {
			this.parms.put(parmname, newparm);
			if(issue.length() > 0)
				issue = new StringBuilder();
		} 
		catch (Exception e) {
			e.printStackTrace();
			return null;
		}		
		return this;
	}
	private String getStringParm(parmname pn) {
		if(parms.get(pn) == null)
			return null;
		return String.valueOf(parms.get(pn));
	}
	public void logIssue() {
		log(getIssueMessage(), true);
	}
	public void logMessage(String message) {
		log(message, false);
	}
	private void log(String message, boolean isError) {
		if(message == null || message.trim().isEmpty())
			return;
		if(validParm(parmname.logger)) {
			getLogger().log(message);
			return;
		}
		if(isError)
			System.err.println(message);
		else
			System.out.println(message);
	}
	/**
	 * @return Boolean indicating if all required parameters have a value.
	 */
	public boolean isComplete() {
		return getIssueMessage().length() == 0;
	}
	/**
	 * @return A message that indicates which parameter(s) are missing, otherwise an empty string.
	 */
	public String getIssueMessage() {
		if(issue.length() == 0) {
			for(parmname pn : parmname.values()) {
				if(!validParm(pn)) {
					buildIssueMessage(issue, pn);
				}
			}
			if(issue.length() > 0) {
				issue.insert(0, "S3FileParms missing required parameter(s): ");
			}
		}
		return issue.toString();
	}
	private void buildIssueMessage(StringBuilder s, parmname pn) {
		if(s.length() != 0)
			s.append(", ");
		s.append(pn);
	}
	public boolean useProfile() {
		return hasValue(parms.get(parmname.profilename));
	}
	public AmazonS3 getS3Client() {
		if(isComplete()) {
			AmazonS3ClientBuilder builder = AmazonS3ClientBuilder.standard().withRegion(getRegion());
			
			if(hasValue(parms.get(parmname.profilename))) {
				builder = builder.withCredentials(
						new ProfileCredentialsProvider(getProfilename()));
			}
			else if(hasValue(parms.get(parmname.accessKey)) && hasValue(parms.get(parmname.secretKey))){
				builder = builder.withCredentials(
						new AWSStaticCredentialsProvider(
								new BasicAWSCredentials(getAccessKey(), getSecretKey())));				
			}
			else {
				/**
				 * com.amazonaws.auth.DefaultAWSCredentialsProviderChain should try to figure out credentials if you get here.
				 * 
				 * 1) You have run this function locally and not explicitly provided profilename or accessKey/secretKey.
				 * This will not be a problem as the DefaultAWSCredentialsProviderChain will find your default profile 
				 * if you have it set in ~/.aws/config, or you have set the equivalent environment variable, etc.
				 *  
				 * 2) In the case of a lambda-backed custom resource being created/updated during a cloudformation template 
				 * execution, the credentials should be discoverable through the ServiceToken tied to the AWS::Lambda::Function
				 * resource, and this should provide sufficient privileges, provided the IAM Role associated with the lambda 
				 * function includes the arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess policy or the equivalent.
				 * 
				 * SEE: https://docs.aws.amazon.com/AWSJavaSDK/latest/javadoc/com/amazonaws/auth/DefaultAWSCredentialsProviderChain.html
				 */
			}
			return builder.build();
		}
		return null;
	}
	private boolean validParm(parmname pn) {
		// Credentials are not required, so any value, including null is allowed.
		if(pn.equals(parmname.profilename))
			return true;
		if(pn.equals(parmname.accessKey))
			return true;
		if(pn.equals(parmname.secretKey))
			return true;
		
		return hasValue(parms.get(pn));
	}
	private boolean hasValue(Object obj) {
		// all other values cannot be null or empty.
		if(obj == null)
			return false;
		if(obj instanceof String) {
			if(((String) obj).trim().isEmpty())
				return false;
		}
		return true;
	}
}