package org.bu.jenkins.active_choices.model;

import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Set;

import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.NamedArgs;

import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.awscore.exception.AwsServiceException;
import software.amazon.awssdk.core.exception.SdkClientException;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.cloudformation.model.Stack;
import software.amazon.awssdk.services.cloudformation.model.Tag;
import software.amazon.awssdk.services.resourcegroupstaggingapi.ResourceGroupsTaggingApiClient;
import software.amazon.awssdk.services.resourcegroupstaggingapi.model.GetResourcesRequest;
import software.amazon.awssdk.services.resourcegroupstaggingapi.model.GetResourcesResponse;
import software.amazon.awssdk.services.resourcegroupstaggingapi.model.ResourceTagMapping;
import software.amazon.awssdk.services.resourcegroupstaggingapi.model.TagFilter;

/**
 * A basic DAO class for listing landscapes and listing aws resources filtered by landscape.
 * 
 * @author wrh
 *
 */
public class LandscapeList extends AbstractModel {

	public LandscapeList(AWSCredentials credentials) {
		super(credentials);
	}
	
	public LandscapeList(AwsCredentialsProvider provider) {
		super(provider);
	}

	/**
	 * Get a description by landscape of each cloudformation stack in which a kuali application is deployed.
	 * @return
	 */
	public Set<String> getDeployedKualiLandscapes() {
		List<Stack> stacks = new StackList(provider).getKualiApplicationStacks();
		Set<String> landscapes = new HashSet<String>();
		for(Stack stack : stacks) {
			Tag matchingTag = stack.tags().stream()
					  .filter(tag -> "landscape".equalsIgnoreCase(tag.key()))
					  .findAny()
					  .orElse(null);
			if(matchingTag != null) {
				landscapes.add(matchingTag.value());
			}
		}
		return landscapes;
	}

	/**
	 * Get a map, keyed by landscape, of every RDS instance that has been deployed for a kuali application stack.
	 * @return
	 */
	public Map<String, String> getDeployedKualiRdsInstancesByLandscape() {
		Map<String, String> instances = new HashMap<String, String>();
		
		try {
			GetResourcesRequest request = GetResourcesRequest.builder()
					.resourceTypeFilters("rds:db")
					.tagFilters(
							TagFilter.builder().key("Service").values("research-administration").build(),
							TagFilter.builder().key("Function").values("kuali").build()
					).build();
			
			ResourceGroupsTaggingApiClient client = ResourceGroupsTaggingApiClient.builder()
					.region(Region.US_EAST_1)
					.credentialsProvider(provider)
					.httpClient(ApacheHttpClient.builder().build())
					.build();
			
			GetResourcesResponse response = client.getResources(request);
			if(response.hasResourceTagMappingList()) {
				outerloop:
				for(ResourceTagMapping mapping : response.resourceTagMappingList()) {
					for(software.amazon.awssdk.services.resourcegroupstaggingapi.model.Tag tag : mapping.tags()) {
						if("landscape".equalsIgnoreCase(tag.key())) {
							instances.put(mapping.resourceARN(), tag.value());
							continue outerloop;
						}
					}
				}
			}
		} 
		catch (AwsServiceException | SdkClientException e) {
			e.printStackTrace();
		}
		
		return instances;
	}

	public Set<Landscape> getBaselineLandscapes() {
		return Landscape.getIds();
	}
	
	public static void main(String[] args) {	
		NamedArgs namedArgs = new NamedArgs(args);
		LandscapeList landscapes = new LandscapeList(new AWSCredentials(namedArgs));
		if("rds".equalsIgnoreCase(namedArgs.get("task"))) {
			for(Entry<String, String> landscape : landscapes.getDeployedKualiRdsInstancesByLandscape().entrySet()) {
				System.out.println(landscape.getKey() + ": " + landscape.getValue());
			}
		}
		else {
			for(String landscape : landscapes.getDeployedKualiLandscapes()) {
				System.out.println(landscape);
			}
		}
	}
}
