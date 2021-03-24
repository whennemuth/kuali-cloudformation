package org.bu.jenkins.active_choices.dao;

import org.bu.jenkins.AWSCredentials;

import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;

	/**
	 * All subclasses represent a dao object and will potentially make aws api calls for data.
	 * An AWSCredentialsProvider and associated constructors are included here.
	 * 
	 * @author wrh
	 *
	 */
public class AbstractDAO {
	
	protected AwsCredentialsProvider provider;
	
	public AbstractDAO(AWSCredentials credentials) {
		this.provider = credentials.getProvider();
	}
	
	public AbstractDAO(AwsCredentialsProvider provider) {
		this.provider = provider;
	}
		
}
