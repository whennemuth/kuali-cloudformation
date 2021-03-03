package org.bu.jenkins;

import java.util.LinkedList;

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
	
	private NamedArgs args;
	private RuntimeException exception;
	
	public AWSCredentials() { }

	public AWSCredentials(String profile) {
		this.args = new NamedArgs().set("profile", profile);
	}
	
	public AWSCredentials(NamedArgs args) {		
		this.args = args;
	}
	
	/**
	 * A provider chain is resolvable if any one of the providers in the chain can find credentials.
	 * 
	 * @param provider
	 * @return
	 */
	private boolean unresolvable(AwsCredentialsProvider provider) {
		@SuppressWarnings("unused")
		AwsCredentials credentials = null;
		try {
			credentials = provider.resolveCredentials();
			exception = null;
		} 
		catch (RuntimeException e) {
			exception = e;
			return true;
		}
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
		AwsCredentialsProvider provider = null;
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
			System.out.println("No valid credentials could be found along provider chain!");
			return null;
		}
		
		return provider;
	}
}
