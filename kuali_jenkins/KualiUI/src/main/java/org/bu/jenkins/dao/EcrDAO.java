package org.bu.jenkins.dao;

import java.util.Collection;
import java.util.Comparator;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.ComparableMavenVersion;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.services.ecr.EcrClient;
import software.amazon.awssdk.services.ecr.model.DescribeImagesRequest;
import software.amazon.awssdk.services.ecr.model.DescribeImagesResponse;
import software.amazon.awssdk.services.ecr.model.ImageDetail;
import software.amazon.awssdk.services.ecr.model.ImageIdentifier;
import software.amazon.awssdk.services.ecr.model.ListImagesRequest;
import software.amazon.awssdk.services.ecr.model.ListImagesResponse;

/**
 * Data access object for and AWS elastic container registry.
 * 
 * @author wrh
 *
 */
public class EcrDAO extends AbstractAwsDAO {

	private Logger logger = LogManager.getLogger(EcrDAO.class.getName());

	private String registryId;
	private String repositoryName;
	private QueryType queryType = QueryType.LIST;
	
	public static enum QueryType {
		LIST, DETAIL
	}
	
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
	public QueryType getQueryType() {
		return queryType;
	}
	public EcrDAO setQueryType(QueryType queryType) {
		this.queryType = queryType;
		return this;
	}
	
	@Override
	public Collection<?> getResources() {
		
		switch(queryType) {
			case DETAIL:
				return getDetails();
			case LIST:
				return getList();
		}
		
		return null;
	}
	
	private Set<ImageIdentifier> getList() {
		
		// Results must be sorted in descending order by the date and version indicated by the maven tag.
		Set<ImageIdentifier> images = new TreeSet<ImageIdentifier>(new Comparator<ImageIdentifier>() {
			@Override public int compare(ImageIdentifier id1, ImageIdentifier id2) {
				return new 
						ComparableMavenVersion(id1.imageTag()).compareTo(new 
						ComparableMavenVersion(id2.imageTag()));
			}			
		});
		
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
	
	private Set<ImageDetail> getDetails() {

		// Results must be sorted in descending order by the date the image was pushed to the registry
		Set<ImageDetail> details = new TreeSet<ImageDetail>(new Comparator<ImageDetail>() {
			@Override public int compare(ImageDetail id1, ImageDetail id2) {
				if(id1 == null && id2 == null) {
					return 0;
				}
				else if(id2 == null) {
					return -1;
				}
				else if(id1 == null) {
					return 1;
				}
				else {
					return id1.imagePushedAt().isAfter(id2.imagePushedAt()) ? -1 : 1;
				}				
			}			
		});
		
		if(getRegistryId() != null && getRepositoryName() != null) {
			DescribeImagesRequest request = DescribeImagesRequest.builder()
					.registryId(getRegistryId())
					.repositoryName(getRepositoryName())
					.build();
			
			EcrClient client = EcrClient.builder()
					.region(getRegion())
					.credentialsProvider(provider)
					.httpClient(ApacheHttpClient.builder().build())
					.build();			
			
			logger.info(String.format("++++++++ API CALL ++++++++ : Getting metadata of all images for %s...", getRepositoryName()));
			
			DescribeImagesResponse response = client.describeImages(request);
			
			if(response.hasImageDetails()) {
				details.addAll(response.imageDetails());
			}
		}

		return details;
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
			
			dao.setQueryType(QueryType.DETAIL);
			((List<ImageDetail>)dao.getResources()).forEach((image) -> {
				System.out.println(image.toString());
			});
			
		}
		else {
			System.out.println("Required \"repository-name\" argument!");
		}
	}

}
