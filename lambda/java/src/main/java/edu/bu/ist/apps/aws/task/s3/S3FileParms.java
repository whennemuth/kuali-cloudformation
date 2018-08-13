package edu.bu.ist.apps.aws.task.s3;

import java.util.LinkedHashMap;
import java.util.Map;

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
		region, bucketname, filename, profilename, logger;
	}
	private Map<parmname, Object> parms = new LinkedHashMap<parmname, Object>();
	
	private StringBuilder issue = new StringBuilder();
	
	public String getRegion() {
		return String.valueOf(parms.get(parmname.region));
	}
	public S3FileParms setRegion(String region) {
		return setParm(parmname.region, region);
	}
	public String getBucketname() {
		return String.valueOf(parms.get(parmname.bucketname));
	}
	public S3FileParms setBucketname(String bucketname) {
		return setParm(parmname.bucketname, bucketname);
	}
	public String getFilename() {
		return String.valueOf(parms.get(parmname.filename));
	}
	public S3FileParms setFilename(String filename) {
		return setParm(parmname.filename, filename);
	}
	public String getProfilename() {
		return String.valueOf(parms.get(parmname.profilename));
	}
	public S3FileParms setProfilename(String profilename) {
		return setParm(parmname.profilename, profilename);
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
	 * @return A message that indicates which parameter(s) are missing, otherwise and empty string.
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
			if(validParm(parmname.profilename)) {
				builder = builder.withCredentials(new ProfileCredentialsProvider(getProfilename()));
			}
			return builder.build();
		}
		return null;
	}
	private boolean validParm(parmname pn) {
		// profilename is not required, so any value, including null is allowed.
		if(pn.equals(parmname.profilename))
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