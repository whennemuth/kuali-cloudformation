package org.bu.jenkins.active_choices.dao;

import java.util.Collection;
import java.util.Map.Entry;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.core.exception.SdkClientException;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.regions.internal.util.EC2MetadataUtils;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.sts.model.GetCallerIdentityResponse;

/**
 * All subclasses represent a dao object and will potentially make aws api calls for data.
 * An AWSCredentialsProvider and associated constructors are included here.
 * 
 * API: https://sdk.amazonaws.com/java/api/latest/
 * 
 * @author wrh
 *
 */
public abstract class AbstractAwsDAO {
	
	private Logger logger = LogManager.getLogger(AbstractAwsDAO.class.getName());
	private String accountId;
	
	protected AwsCredentialsProvider provider;
	
	public static final Region DEFAULT_REGION = Region.US_EAST_1;
	
	public AbstractAwsDAO(AWSCredentials credentials) {
		this.provider = credentials.getProvider();
	}
	
	public AbstractAwsDAO(AwsCredentialsProvider provider) {
		this.provider = provider;
	}
	
	public String getAccountId() {
		if(this.accountId == null) {
			try {
				accountId = EC2MetadataUtils.getInstanceInfo().getAccountId();
			}
			catch(SdkClientException e) {
				logger.info("++++++++ API CALL ++++++++ : Getting current account number...");
				
				StsClient client = StsClient.builder()
						.region(getRegion())
						.credentialsProvider(provider)
						.httpClient(ApacheHttpClient.builder().build())
						.build();
				
				GetCallerIdentityResponse response = client.getCallerIdentity();			
				accountId = response.account();			
			}			
		}

		return this.accountId;
	}
	
	public Region getRegion() {
		Region region = null;
		for(Entry<String, String> entry : System.getenv().entrySet()) {
			if("AWS_REGION".equalsIgnoreCase(entry.getKey()) || "REGION".equalsIgnoreCase(entry.getKey())) {
				region = Region.of(entry.getValue());
			}			
		}
		if(region == null) {
			try {
				region = Region.of(EC2MetadataUtils.getEC2InstanceRegion().toLowerCase());
			}
			catch(SdkClientException e) {
				logger.warn(String.format("Could not determine the region! Defaulting to %s", DEFAULT_REGION.id()));
				region = DEFAULT_REGION;
			}
		}
		return region;
	}
	
	
	
	@Override
	public String toString() {
		StringBuilder builder = new StringBuilder();
		builder.append("AbstractDAO [getAccountId()=").append(getAccountId()).append(", getRegion()=")
				.append(getRegion()).append("]");
		return builder.toString();
	}

	public abstract Collection<?> getResources();
	
	static void printHeader(String msg) {
		final String border = "----------------------------------------------------------------------------------------------------";
		System.out.println("");
		System.out.println(border);
		System.out.println("             " + msg);
		System.out.println(border);
	}
	
	public static void main(String[] args) {
		NamedArgs namedArgs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		AbstractAwsDAO dao = new AbstractAwsDAO(AWSCredentials.getInstance(namedArgs)) {
			@Override public Collection<?> getResources() { return null; }					
		};
		System.out.println(dao);
	}
		
}
