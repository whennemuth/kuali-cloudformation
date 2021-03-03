package org.bu.jenkins.active_choices.model;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.NamedArgs;

import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.awscore.exception.AwsServiceException;
import software.amazon.awssdk.core.exception.SdkClientException;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.cloudformation.CloudFormationClient;
import software.amazon.awssdk.services.cloudformation.model.DescribeStacksRequest;
import software.amazon.awssdk.services.cloudformation.model.DescribeStacksResponse;
import software.amazon.awssdk.services.cloudformation.model.ListStacksRequest;
import software.amazon.awssdk.services.cloudformation.model.ListStacksResponse;
import software.amazon.awssdk.services.cloudformation.model.Stack;
import software.amazon.awssdk.services.cloudformation.model.StackStatus;
import software.amazon.awssdk.services.cloudformation.model.StackSummary;
import software.amazon.awssdk.services.cloudformation.model.Tag;

/**
 * A basic DAO class for cloudformation stack information acquired through the aws api.
 * 
 * @author wrh
 *
 */
public class StackList extends AbstractModel {
	
	public StackList(AWSCredentials credentials) {
		super(credentials);
	}
	
	public StackList(AwsCredentialsProvider provider) {
		super(provider);
	}
	
	private CloudFormationClient getClient() {
		return CloudFormationClient.builder()
				.region(Region.US_EAST_1)
				.credentialsProvider(provider)
				.httpClient(ApacheHttpClient.builder().build())
				.build();
	}
	
	/**
	 * Get a list of stack summaries for anything with the term "kuali" in it.
	 * This will include nested stacks.
	 * @return
	 */
	public List<StackSummary> getKualiStackSummaries() {
		ListStacksResponse response = null;
		List<StackSummary> filtered = new ArrayList<StackSummary>();
		try {
			response = getClient().listStacks(ListStacksRequest.builder()
					.stackStatusFilters(getAllButDeletedStackStatuses()).build());
			for (StackSummary summary : response.stackSummaries()) {
				if(summary.rootId() == null) {
					if(summary.stackName().toLowerCase().startsWith("kuali")) {
						filtered.add(summary);
					}
				}
			}
		} 
		catch (AwsServiceException | SdkClientException e) {			
			e.printStackTrace();
		}
		
		return filtered;
	}
	
	/**
	 * Get a list of stacks for kuali. These will be any stack tagged with "kuali" as the function.
	 * This will include nested stacks.
	 * @return
	 */
	public List<Stack> getKualiStacks() {
		DescribeStacksResponse response = null;
		List<Stack> filtered = new ArrayList<Stack>();
		try {
			response = getClient().describeStacks(DescribeStacksRequest.builder().build());
			for(Stack stack : response.stacks()) {
				if(stack.hasTags()) {
					int foundTags = 0;
					for(Tag tag : stack.tags()) {
						if(tag.key().equalsIgnoreCase("Service") && tag.value().equalsIgnoreCase("research-administration")) {
							foundTags++;
						}
						if(tag.key().equalsIgnoreCase("Function") && tag.value().equalsIgnoreCase("kuali")) {
							foundTags++;
						}
						if(foundTags == 2) {
							filtered.add(stack);
							break;
						}
					}
				}
			}
		} 
		catch (AwsServiceException | SdkClientException e) {
			e.printStackTrace();
		}
		
		return filtered;
	}
	
	/**
	 * Get a list of stack for the kuali application. These will only include the primary application stacks that comprise kuali 
	 * running as a containerized service on ec2 instances. This will NOT include nested stacks.
	 * @return
	 */
	public List<Stack> getKualiApplicationStacks() {
		List<Stack> stacks = getKualiStacks();
		List<Stack> filtered = new ArrayList<Stack>();
		for(Stack stack : stacks) {
			if(stack.rootId() == null) {
				for(Tag tag : stack.tags()) {
					if(tag.key().equalsIgnoreCase("Category") && tag.value().equalsIgnoreCase("application")) {
						filtered.add(stack);
					}
				}
			}
		}
		return filtered;
	}
	
	/**
	 * Get the kuali application stack tagged for the specified landscape.
	 * @param landscape
	 * @return The stack, or null if no such stack can be found as tagged.
	 */
	public Stack getKualiApplicationStackForLandscape(String landscape) {
		List<Stack> stacks = getKualiApplicationStacks();
		for(Stack stack : stacks) {
			for(Tag tag : stack.tags()) {
				if(tag.key().equalsIgnoreCase(landscape)) {
					return stack;
				}
			}
		}
		return null;
	}
	
	public static Set<StackStatus> getAllButDeletedStackStatuses() {
		Set<StackStatus> statuses = new HashSet<StackStatus>(StackStatus.knownValues());
		statuses.remove(StackStatus.DELETE_COMPLETE);
		return statuses;
	}
	
	public static void main(String[] args) {
		StackList stacklist = new StackList(new AWSCredentials(new NamedArgs(args)));		
		for (Stack stack : stacklist.getKualiStacks()) {
			System.out.println(stack.stackName());
		}
	}
}