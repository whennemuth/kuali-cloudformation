package org.bu.jenkins.dao;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;
import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.dao.cache.StackDAOCache;
import org.bu.jenkins.mvc.model.CloudFormationStack;
import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

import com.fasterxml.jackson.annotation.JsonAutoDetect.Visibility;
import com.fasterxml.jackson.annotation.PropertyAccessor;
import com.fasterxml.jackson.core.JsonGenerator;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.Version;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.databind.SerializerProvider;
import com.fasterxml.jackson.databind.module.SimpleModule;
import com.fasterxml.jackson.databind.ser.std.StdSerializer;

import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.awscore.exception.AwsServiceException;
import software.amazon.awssdk.core.exception.SdkClientException;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
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
public class StackDAO extends AbstractAwsDAO {
	
	private Logger logger = LogManager.getLogger(StackDAO.class.getName());
	
	public static final StackDAOCache CACHE = new StackDAOCache();
	
	public StackDAO(AWSCredentials credentials) {
		super(credentials);
	}
	
	public StackDAO(AwsCredentialsProvider provider) {
		super(provider);
	}
	
	private CloudFormationClient getClient() {
		return CloudFormationClient.builder()
				.region(getRegion())
				.credentialsProvider(provider)
				.httpClient(ApacheHttpClient.builder().build())
				.build();
	}
	
	/**
	 * Get a list of stack summaries for anything with the term "kuali" in it.
	 * This will include nested stacks.
	 * @return
	 */
	public List<StackSummary> getKualiStackSummaries(boolean reload) {
		EntryMessage m = logger.traceEntry("getKualiStackSummaries()");
		
		if(CACHE.stacksSummariesAlreadyLoaded() && ! reload) {
			logger.info("++++++++ CACHE USE ++++++++ : Using cache for kuali stack summaries");
			logger.traceExit(m);
			return new ArrayList<StackSummary>(CACHE.getSummaries());
		}

		ListStacksResponse response = null;
		List<StackSummary> filtered = new ArrayList<StackSummary>();
		try {
			logger.info("++++++++ API CALL ++++++++ : Getting kuali stack summaries");
			response = getClient().listStacks(ListStacksRequest.builder()
					.stackStatusFilters(getAllButDeletedStackStatuses()).build());
			for (StackSummary summary : response.stackSummaries()) {
				if(summary.rootId() == null) {
					if(summary.stackName().toLowerCase().startsWith("kuali")) {
						filtered.add(summary);
						CACHE.put(summary);
					}
				}
			}
			CACHE.setLoaded(true);
		} 
		catch (AwsServiceException | SdkClientException e) {			
			e.printStackTrace();
		}
		
		logger.traceExit(m);
		return filtered;
	}
	
	/**
	 * Get a list of stacks for kuali. These will be any stack tagged with "kuali" as the function.
	 * This will include nested stacks.
	 * @return
	 */
	public List<Stack> getKualiStacks(boolean reload) {
		EntryMessage m = logger.traceEntry("getKualiStacks()");
		
		if(CACHE.stacksAlreadyLoaded() && ! reload) {
			logger.info("++++++++ CACHE USE ++++++++ : Using cache for kuali stacks");
			logger.traceExit(m);
			return new ArrayList<Stack>(CACHE.getStacks());
		}
		
		DescribeStacksResponse response = null;
		List<Stack> filtered = new ArrayList<Stack>();
		try {
			logger.info("++++++++ API CALL ++++++++ : Getting kuali stacks");
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
							CACHE.put(stack);
							break;
						}
					}
				}
			}
			CACHE.setLoaded(true);
		} 
		catch (AwsServiceException | SdkClientException e) {
			e.printStackTrace();
		}
		
		logger.traceExit(m);
		return filtered;
	}
	
	/**
	 * Get a list of stacks for the kuali application. These will only include the primary application stacks that comprise kuali 
	 * running as a containerized service on ec2 instances. This will NOT include nested stacks.
	 * @return
	 */
	private List<Stack> _getKualiApplicationStacks() {
		List<Stack> stacks = getKualiStacks(false);
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
	 * Get a list of stacks for the kuali application. These will only include the primary application stacks that comprise kuali 
	 * running as a containerized service on ec2 instances. This will NOT include nested stacks.
	 * @return
	 */
	public List<CloudFormationStack> getKualiApplicationStacks() {
		List<Stack> stacks = _getKualiApplicationStacks();
		List<CloudFormationStack> filtered = new ArrayList<CloudFormationStack>();
		for(Stack stack : stacks) {
			filtered.add(new CloudFormationStack(stack));
		}
		return filtered;
	}
	
	public Stack getKualiStackApplicationStack(String landscape) {
		Stack match = null;
		List<Stack> stacks = _getKualiApplicationStacks();
		for(Stack stack : stacks) {
			if(landscape.equalsIgnoreCase(new CloudFormationStack(stack).getLandscape())) {
				match = stack;
			}
		}
		return match;
	}
	
	public String getKualiStackApplicationStackJson(String landscape) {
		return getKualiStackApplicationStackJson(landscape, false);
	}
	
	public String getKualiStackApplicationStackJson(String landscape, boolean formatted) {
		Stack stack = getKualiStackApplicationStack(landscape);
		if(stack == null) {
			return "{}";
		}
		ObjectMapper objectMapper = new ObjectMapper();
		// objectMapper.setVisibility(PropertyAccessor.FIELD, Visibility.ANY);

		@SuppressWarnings("serial")
		class CustomStackSerializer extends StdSerializer<Stack> {
		    
		    public CustomStackSerializer() {
		        this(null);
		    }

		    public CustomStackSerializer(Class<Stack> t) {
		        super(t);
		    }

		    @Override
		    public void serialize(
		      Stack stack, JsonGenerator jsonGenerator, SerializerProvider serializer) throws IOException {
		        jsonGenerator.writeStartObject();
		        
		        jsonGenerator.writeStringField("stackName", stack.stackName());
		        jsonGenerator.writeStringField("stackId", stack.stackId());
		        jsonGenerator.writeStringField("roleARN", stack.roleARN());
		        jsonGenerator.writeStringField("stackStatusAsString", stack.stackStatusAsString());
		        jsonGenerator.writeStringField("stackStatusReason", stack.stackStatusReason());
		        jsonGenerator.writeStringField("creationTime", stack.creationTime() == null ? "null" : stack.creationTime().toString());
		        jsonGenerator.writeStringField("deletionTime", stack.deletionTime() == null ? "null" : stack.toString());
		        jsonGenerator.writeStringField("description", stack.description());
		        
		        jsonGenerator.writeEndObject();
		    }
		}

		try {
			SimpleModule module = new SimpleModule("CustomStackSerializer", new Version(1, 0, 0, null, null, null));
			module.addSerializer(Stack.class, new CustomStackSerializer());
			objectMapper.registerModule(module);
			if(formatted) {
				return objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(stack);
			}
			else {
				return objectMapper.writeValueAsString(stack);
			}
		} 
		catch (JsonProcessingException e) {
			e.printStackTrace();
			return String.format("{\"error\":\"%s\"}", e.getMessage().replaceAll("\"", ""));
		}
	}

	@Override
	public Collection<?> getResources() {
		return getKualiApplicationStacks();
	}
	
	public static Set<StackStatus> getAllButDeletedStackStatuses() {
		Set<StackStatus> statuses = new HashSet<StackStatus>(StackStatus.knownValues());
		statuses.remove(StackStatus.DELETE_COMPLETE);
		return statuses;
	}
	
	public static void main(String[] args) {
		NamedArgs namedArgs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		StackDAO dao = new StackDAO(AWSCredentials.getInstance(namedArgs));		
		for (Stack stack : dao.getKualiStacks(false)) {
			System.out.println(stack.stackName());
		}
		
		if(namedArgs.has("landscape")) {
			System.out.println(dao.getKualiStackApplicationStackJson(namedArgs.get("landscape"), true));
		}
	}
}