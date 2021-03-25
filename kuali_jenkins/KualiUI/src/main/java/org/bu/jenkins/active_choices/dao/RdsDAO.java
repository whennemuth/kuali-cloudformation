package org.bu.jenkins.active_choices.dao;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;
import java.util.TreeMap;

import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.CaseInsensitiveEnvironment;
import org.bu.jenkins.LoggingStarterImpl;
import org.bu.jenkins.NamedArgs;
import org.bu.jenkins.active_choices.dao.RdsDAOCache.ProcessItem;
import org.bu.jenkins.active_choices.dao.RdsDAOCache.TestItem;
import org.bu.jenkins.active_choices.model.Landscape;
import org.bu.jenkins.active_choices.model.RdsInstance;
import org.bu.jenkins.active_choices.model.RdsSnapshot;

import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.awscore.exception.AwsServiceException;
import software.amazon.awssdk.core.exception.SdkClientException;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.rds.RdsClient;
import software.amazon.awssdk.services.rds.model.DBSnapshot;
import software.amazon.awssdk.services.rds.model.DescribeDbSnapshotsRequest;
import software.amazon.awssdk.services.rds.model.DescribeDbSnapshotsResponse;
import software.amazon.awssdk.services.resourcegroupstaggingapi.ResourceGroupsTaggingApiClient;
import software.amazon.awssdk.services.resourcegroupstaggingapi.model.GetResourcesRequest;
import software.amazon.awssdk.services.resourcegroupstaggingapi.model.GetResourcesResponse;
import software.amazon.awssdk.services.resourcegroupstaggingapi.model.ResourceTagMapping;
import software.amazon.awssdk.services.resourcegroupstaggingapi.model.TagFilter;

import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;
import org.apache.logging.log4j.LogManager;


public class RdsDAO extends AbstractDAO {

	private Logger logger = LogManager.getLogger(RdsDAO.class.getName());
	
	public static final RdsDAOCache CACHE = new RdsDAOCache();
	
	public RdsDAO(AwsCredentialsProvider provider) {
		super(provider);
	}
	
	public RdsDAO(AWSCredentials credentials) {
		super(credentials);
	}
	
	public Map<String, List<RdsInstance>> getDeployedKualiRdsInstancesGroupedByBaseline() {
		Map<String, List<RdsInstance>> rdsInstances = new TreeMap<String, List<RdsInstance>>(new Comparator<String>() {
			@Override public int compare(String key1, String key2) {
				return Landscape.fromAlias(key1).getOrder() - Landscape.fromAlias(key2).getOrder();
			}			
		});
		
		loadAllKualiRdsInstances(false, false);
		
		for(Landscape landscape : Landscape.values()) {
			List<RdsInstance> instances = new ArrayList<RdsInstance>();
			CACHE.processAll(new ProcessItem() {
				@Override public void process(RdsInstance rds) {
					if(Landscape.fromAlias(rds.getBaseline()) != null) {
						if(Landscape.fromAlias(rds.getBaseline()).equals(landscape)) {
							instances.add(rds);
						}
					}
				}
			});
			rdsInstances.put(landscape.getId(), instances);
		}
		return rdsInstances;
	}
	
	/**
	 * Get a map, keyed by landscape, of every RDS instance that has been deployed for a kuali application stack.
	 * @return
	 */
	public Collection<RdsInstance> getDeployedKualiRdsInstances() {		
		loadAllKualiRdsInstances(false, false);
		return CACHE.getValues();
	}
	
	/**
	 * Load all rds instances that whose tagging indicates kuali 
	 * @param reload
	 * @param loadSnapshots
	 */
	private void loadAllKualiRdsInstances(boolean reload, boolean loadSnapshots) {
		
		EntryMessage m = logger.traceEntry("loadAllKualiRdsInstances(reload={}, loadSnapshots={})", reload, loadSnapshots);
		
		if(CACHE.alreadyLoaded() && ! reload) {
			logger.info("++++++++ CACHE USE ++++++++ : Using cached resource mapping list for kuali rds instances");
			logger.traceExit(m);
			return;
		}
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
			
			logger.info("++++++++ API CALL ++++++++ : Making api call for resource mapping list for kuali rds instances...");
			GetResourcesResponse response = client.getResources(request);
			if(response.hasResourceTagMappingList()) {
				
				outerloop:
				for(ResourceTagMapping mapping : response.resourceTagMappingList()) {
					RdsInstance rdsInstance = new RdsInstance(mapping.resourceARN());
					for(software.amazon.awssdk.services.resourcegroupstaggingapi.model.Tag tag : mapping.tags()) {
						rdsInstance.putTag(tag.key(), tag.value());						
					}
					if(loadSnapshots) {
						loadSnapshots(rdsInstance);
					}
					CACHE.add(rdsInstance);
					continue outerloop;
				}
				
			}
		} 
		catch (AwsServiceException | SdkClientException e) {
			e.printStackTrace();
		}
		
		logger.traceExit(m);
	}

	/**
	 * Get the rds instance by the specified arn. If it can be obtained from the cache, it will probably not have the
	 * snapshots collection populated as they are lazy-loaded here to cut down on api call wait time at earlier points. 
	 * @param rdsArn
	 * @return
	 */
	public RdsInstance getRdsInstanceByArn(String rdsArn) {
		RdsInstance instance = CACHE.get(rdsArn);
		if(instance == null || instance.getTags().isEmpty()) {
			// Load all kuali rds instances - the instance we need will be one of them.
			loadAllKualiRdsInstances(true, false);
			instance = CACHE.get(rdsArn);
			if(instance != null) {
				loadSnapshots(instance);
			}
		}
		else if( ! instance.snapshotsLoaded()) {
			loadSnapshots(instance);
		}
		CACHE.add(instance);
		return instance;
	}
	
	public RdsInstance getRdsInstanceByLandscape(String landscape) {
		return getRdsInstanceByLandscape(landscape, true);
	}
		
	private RdsInstance getRdsInstanceByLandscape(String landscape, boolean recurse) {
		RdsInstance rdsInstance = CACHE.getItem(new TestItem() {
			@Override public boolean match(RdsInstance instance) {
				return landscape.equals(instance.getLandscape());
			}			
		});
		if(rdsInstance == null && recurse) {
			loadAllKualiRdsInstances(true, false);
			rdsInstance = getRdsInstanceByLandscape(landscape, false);
		}
		if(rdsInstance != null && ! rdsInstance.snapshotsLoaded()) {
			loadSnapshots(rdsInstance);
		}
		return rdsInstance;
	}

	/**
	 * Make the aws api calls to get the snapshot data for the specified rds instance.
	 */
	private RdsInstance loadSnapshots(RdsInstance rdsInstance) {
		
		EntryMessage m = logger.traceEntry("loadSnapshots(RdsInstance.getArn()={})", rdsInstance.getArn());
		
		if(rdsInstance.snapshotsLoaded()) {
			logger.info("++++++++ CACHE USE ++++++++ : Snapshots already loaded for {}", rdsInstance.getArn());
			return rdsInstance;
		}
		if(hasValue(rdsInstance.getArn())) {
			try {
				DescribeDbSnapshotsRequest request = DescribeDbSnapshotsRequest.builder()
						.dbInstanceIdentifier(rdsInstance.getArn())
						.build();
				
				RdsClient client = RdsClient.builder()
						.region(Region.US_EAST_1)
						.credentialsProvider(provider)
						.httpClient(ApacheHttpClient.builder().build())
						.build();
				
				logger.info("++++++++ API CALL ++++++++ : Loading snapshots for {}...", rdsInstance.getArn());
				DescribeDbSnapshotsResponse response = client.describeDBSnapshots(request);
				
				if(response.hasDbSnapshots()) {
					for(DBSnapshot snapshot : response.dbSnapshots()) {
						if("available".equalsIgnoreCase(snapshot.status())) {
							rdsInstance.putSnapshot(new RdsSnapshot(
								rdsInstance,
								snapshot.snapshotCreateTime(),
								snapshot.dbSnapshotArn(),
								snapshot.snapshotType()
							));
						}
					}
				}
			} 
			catch (AwsServiceException | SdkClientException e) {
				e.printStackTrace();
			}
		}
		logger.traceExit(m);
		return rdsInstance;
	}
		
	private static boolean hasValue(Object obj) {
		if(obj == null)
			return false;
		if(obj.toString().isBlank())
			return false;
		return true;
	}
	
	public static Object test(String task, NamedArgs namedArgs) {
		RdsDAO rdsDAO = new RdsDAO(AWSCredentials.getInstance(namedArgs));
		switch(task) {
			case "landscape": 
				printHeader(task);
				Collection<RdsInstance> rdsInstances = rdsDAO.getDeployedKualiRdsInstances();
				for(RdsInstance rdsInstance : rdsInstances) {
					System.out.println(rdsInstance);					
				}
				break;
			case "baseline": 
				printHeader(task);
				Map<String, List<RdsInstance>> map = rdsDAO.getDeployedKualiRdsInstancesGroupedByBaseline();
				StringBuilder builder = new StringBuilder();
				builder.append("RdsByBaseline [rdsInstances=\n");
				final String offset = "   ";
				for(Entry<String, List<RdsInstance>> baseline : map.entrySet()) {
					builder.append(offset)
					.append(baseline.getKey())
					.append(": \n");
					for(RdsInstance instance : baseline.getValue()) {
						builder.append(offset).append(offset)
						.append(instance.getArn())
						.append("\n");
					}
				}
				builder.append("]");
				System.out.println(builder.toString());				
				break;
			case "instance":
				RdsInstance rds = null;
				if(namedArgs.has("arn")) {
					printHeader(task + " (" + namedArgs.get("arn") + ")");
					rds = rdsDAO.getRdsInstanceByArn(namedArgs.get("arn"));
				}
				else if(namedArgs.has("landscape")) {
					printHeader(task + " (" + namedArgs.get("landscape") + ")");
					rds = rdsDAO.getRdsInstanceByLandscape(namedArgs.get("landscape"));
				}
				else {
					System.out.println("Missing: arn or landscape parameter");
					return null;
				}
				System.out.println(rds);
				return rds;
		}
		return null;
	}

	public static void printHeader(String msg) {
		final String border = "----------------------------------------------------------------------------------------------------";
		System.out.println("");
		System.out.println(border);
		System.out.println("             " + msg);
		System.out.println(border);
	}
	
	public static void main(String[] args) {
		NamedArgs namedArgs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		if( ! namedArgs.has("task")) {
			System.out.println("Missing: task parameter");
			return;
		}
		String task = namedArgs.get("task").toLowerCase();
		
		if("all".equals(task)) {
			
			test("landscape", namedArgs);
			
			test("baseline", namedArgs);
			
			RdsInstance rds = (RdsInstance) test("instance", namedArgs);
			CACHE.remove(rds);
			namedArgs.set("arn", rds.getArn());
			
			test("instance", namedArgs);
		}
		else {
			test(task, namedArgs);
		}
	}

}
