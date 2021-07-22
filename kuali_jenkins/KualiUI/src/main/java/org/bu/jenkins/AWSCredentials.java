package org.bu.jenkins;

import java.util.LinkedList;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;
import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

import software.amazon.awssdk.auth.credentials.AwsCredentials;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProviderChain;
import software.amazon.awssdk.auth.credentials.EnvironmentVariableCredentialsProvider;
import software.amazon.awssdk.auth.credentials.InstanceProfileCredentialsProvider;
import software.amazon.awssdk.auth.credentials.ProfileCredentialsProvider;
import software.amazon.awssdk.auth.credentials.SystemPropertyCredentialsProvider;

/**
 * This class constructs a variant of the default aws credentials provider chain and puts the different credentials providers 
 * in an order that makes sense for the environment the application is running in. A null is returned if no provider in the
 * chain can resolve any credentials.
 * 
 * @author wrh
 *
 */
public class AWSCredentials {
	
	private Logger logger = LogManager.getLogger(AWSCredentials.class.getName());
	
	private static AWSCredentials instance;
	
	/**
	 * Make this a singleton class (Only need to get the instance once, otherwise costly repetition of provider chain resolution).
	 * @param profile
	 * @return
	 */
	public static AWSCredentials getInstance(Object obj) {
		if(instance == null) {
			synchronized(AWSCredentials.class) {
				if(instance == null) {
					if(obj instanceof String)
						instance = new AWSCredentials((String) obj);
					else if(obj instanceof NamedArgs)
						instance = new AWSCredentials((NamedArgs) obj);
					else
						instance = new AWSCredentials();
				}
			}
		}
		return instance;
	}
	
	public static AWSCredentials getInstance() {
		return getInstance(null);
	}
	
	private NamedArgs args;
	private RuntimeException exception;
	private AwsCredentialsProvider provider;
	
	private AWSCredentials() { 
		super();
	}

	private AWSCredentials(String profile) {
		NamedArgs namedArgs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()));
		this.args = namedArgs.set("profile", profile);
	}
	
	private AWSCredentials(NamedArgs args) {		
		this.args = args;
	}
	
	/**
	 * A provider chain is resolvable if any one of the providers in the chain can find credentials.
	 * 
	 * @param provider
	 * @return
	 */
	private boolean unresolvable(AwsCredentialsProvider provider) {
		EntryMessage m = logger.traceEntry("unresolvable(provider=[Object])");
		@SuppressWarnings("unused")
		AwsCredentials credentials = null;
		try {
			credentials = provider.resolveCredentials();
			exception = null;
		} 
		catch (RuntimeException e) {
			exception = e;
			logger.traceExit(m, "true");
			return true;
		}
		logger.traceExit(m, "false");
		return false;
	}
	
	public boolean unresolvable() {
		return exception != null;
	}
	
	public RuntimeException getException() {
		return exception;
	}

	/**
	 * Get the resolved provider chain.
	 * @return
	 */
	public AwsCredentialsProvider getProvider() {
		EntryMessage m = logger.traceEntry("getProvider()");
		if(provider == null) {
			logger.trace("AwsCredentialsProvider not built, building...");
			LinkedList<AwsCredentialsProvider> chain = new LinkedList<AwsCredentialsProvider>();
			chain.add(EnvironmentVariableCredentialsProvider.create());
			chain.add(SystemPropertyCredentialsProvider.create());
			if(args == null || args.get("profile") == null) {
				chain.addFirst(InstanceProfileCredentialsProvider.create());
				chain.addLast(ProfileCredentialsProvider.create());
			}
			else {
				chain.addFirst(ProfileCredentialsProvider.create(args.get("profile")));
				chain.addLast(InstanceProfileCredentialsProvider.create());
			}
			
			provider = AwsCredentialsProviderChain.builder().credentialsProviders(chain).build();
			
			if(unresolvable(provider)) {
				logger.warn("No valid credentials could be found along provider chain!");
				logger.traceExit(m, "null");
				return null;
			}
		}
		
		logger.traceExit(m, "[Object]");
		return provider;
	}
}
