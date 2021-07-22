package org.bu.jenkins.active_choices.dao;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.services.ecr.EcrClient;
import software.amazon.awssdk.services.ecr.model.ImageIdentifier;
import software.amazon.awssdk.services.ecr.model.ListImagesRequest;
import software.amazon.awssdk.services.ecr.model.ListImagesResponse;

public class EcrDAO extends AbstractAwsDAO {

	private Logger logger = LogManager.getLogger(EcrDAO.class.getName());

	private String registryId;
	private String repositoryName;
	
	public EcrDAO(AWSCredentials credentials) {
		super(credentials);
	}
	public EcrDAO(AwsCredentialsProvider provider) {
		super(provider);
	}

	public String getRegistryId() {
		if(registryId == null) {
			registryId = getAccountId();
		}
		return registryId;
	}
	public EcrDAO setRegistryId(String registryId) {
		this.registryId = registryId;
		return this;
	}
	public String getRepositoryName() {
		return repositoryName;
	}
	public EcrDAO setRepositoryName(String repositoryName) {
		this.repositoryName = repositoryName;
		return this;
	}

	@Override
	public Collection<?> getResources() {
		
		List<ImageIdentifier> images = new ArrayList<ImageIdentifier>();
		if(getRegistryId() != null && getRepositoryName() != null) {
			ListImagesRequest request = ListImagesRequest.builder()
					.registryId(getRegistryId())
					.repositoryName(getRepositoryName())
					.build();
			
			EcrClient client = EcrClient.builder()
					.region(getRegion())
					.credentialsProvider(provider)
					.httpClient(ApacheHttpClient.builder().build())
					.build();
			
			logger.info(String.format("++++++++ API CALL ++++++++ : Getting versions of %s...", getRepositoryName()));
			
			ListImagesResponse response = client.listImages(request);
			
			if(response.hasImageIds()) {
				images.addAll(response.imageIds());
			}			
		}
		
		return images;
	}
	

	@SuppressWarnings("unchecked")
	public static void main(String[] args) {
		NamedArgs namedArgs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		final String repoKey = "repository-name";
		final String registryKey = "registry-id";
		
		if(namedArgs.has(repoKey)) {
			EcrDAO dao = new EcrDAO(AWSCredentials.getInstance(namedArgs))
					.setRepositoryName(namedArgs.get(repoKey));
			if(namedArgs.has(registryKey)) {
				dao.setRegistryId(namedArgs.get(registryKey));
			}
			((List<ImageIdentifier>)dao.getResources()).forEach((image) -> {
				System.out.println(
					String.format("%s/%s:%s", dao.getRegistryId(), dao.getRepositoryName(), image.imageTag())
				);
			});
		}
		else {
			System.out.println("Required \"repository-name\" argument!");
		}
	}

}
