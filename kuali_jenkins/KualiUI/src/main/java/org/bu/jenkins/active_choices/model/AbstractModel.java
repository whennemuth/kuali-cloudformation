package org.bu.jenkins.active_choices.model;

import org.bu.jenkins.AWSCredentials;

import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;

/**
 * All subclasses represent a model and will potentially make aws api calls for data to populate that model.
 * An AWSCredentialsProvider and associated constructors are included here.
 * 
 * @author wrh
 *
 */
public abstract class AbstractModel {

	protected AwsCredentialsProvider provider;
	
	public AbstractModel(AWSCredentials credentials) {
		this.provider = credentials.getProvider();
	}
	
	public AbstractModel(AwsCredentialsProvider provider) {
		this.provider = provider;
	}

}