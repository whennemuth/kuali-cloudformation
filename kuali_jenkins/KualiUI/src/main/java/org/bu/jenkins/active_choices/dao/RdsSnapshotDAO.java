package org.bu.jenkins.active_choices.dao;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;
import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.active_choices.dao.cache.RdsSnapshotDAOCache;
import org.bu.jenkins.active_choices.dao.cache.BasicDAOCache.ProcessItem;
import org.bu.jenkins.active_choices.model.AbstractAwsResource;
import org.bu.jenkins.active_choices.model.Landscape;
import org.bu.jenkins.active_choices.model.RdsInstance;
import org.bu.jenkins.active_choices.model.RdsSnapshot;
import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.awscore.exception.AwsServiceException;
import software.amazon.awssdk.core.exception.SdkClientException;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.resourcegroupstaggingapi.ResourceGroupsTaggingApiClient;
import software.amazon.awssdk.services.resourcegroupstaggingapi.model.GetResourcesRequest;
import software.amazon.awssdk.services.resourcegroupstaggingapi.model.GetResourcesResponse;
import software.amazon.awssdk.services.resourcegroupstaggingapi.model.ResourceTagMapping;
import software.amazon.awssdk.services.resourcegroupstaggingapi.model.TagFilter;

public class RdsSnapshotDAO extends AbstractAwsDAO {

	private Logger logger = LogManager.getLogger(RdsSnapshotDAO.class.getName());
	
	public static final RdsSnapshotDAOCache CACHE = new RdsSnapshotDAOCache();
	
	public RdsSnapshotDAO(AWSCredentials credentials) {
		super(credentials);
	}
	
	public RdsSnapshotDAO(AwsCredentialsProvider provider) {
		super(provider);
	}

	private void loadAllKualiRdsSnapshots(boolean reload) {
		EntryMessage m = logger.traceEntry("loadAllKualiRdsSnapshots(reload={})", reload);
		
		if(CACHE.alreadyLoaded() && ! reload) {
			logger.info("++++++++ CACHE USE ++++++++ : Using cached resource mapping list for kuali rds snapshots");
			logger.traceExit(m);
			return;
		}
		try {
			GetResourcesRequest request = GetResourcesRequest.builder()
					.resourceTypeFilters("rds:snapshot")
					.tagFilters(
							TagFilter.builder().key("Service").values("research-administration").build(),
							TagFilter.builder().key("Function").values("kuali").build()
					).build();
			
			ResourceGroupsTaggingApiClient client = ResourceGroupsTaggingApiClient.builder()
					.region(getRegion())
					.credentialsProvider(provider)
					.httpClient(ApacheHttpClient.builder().build())
					.build();
			
			logger.info("++++++++ API CALL ++++++++ : Making api call for resource mapping list for kuali rds snapshots...");
			
			GetResourcesResponse response = client.getResources(request);
			if(response.hasResourceTagMappingList()) {
				
				for(ResourceTagMapping mapping : response.resourceTagMappingList()) {
					RdsSnapshot snapshot = new RdsSnapshot(mapping.resourceARN());
					for(software.amazon.awssdk.services.resourcegroupstaggingapi.model.Tag tag : mapping.tags()) {
						snapshot.putTag(tag.key(), tag.value());				
					}
					CACHE.put(snapshot);
					continue;
				}				
			}
			CACHE.setLoaded(true);
		} 
		catch (AwsServiceException | SdkClientException e) {
			e.printStackTrace();
		}
	
		logger.traceExit(m);
	}
	
	public List<RdsSnapshot> getAllKualiRdsSnapshots() {
		loadAllKualiRdsSnapshots(false);
		List<RdsSnapshot> snapshots = new ArrayList<RdsSnapshot>();
		for(AbstractAwsResource resource : CACHE.getValues()) {
			snapshots.add((RdsSnapshot) resource);
		}
		return snapshots;
	}
	
	public List<RdsSnapshot> getAllOrphanedKualiRdsSnapshots() {
		if(this.provider != null) {
			return getAllOrphanedKualiRdsSnapshots(new RdsInstanceDAO(provider));
		}
		return null;
	}
		
	public List<RdsSnapshot> getAllOrphanedKualiRdsSnapshots(RdsInstanceDAO instanceDAO) {
		List<RdsSnapshot> orphaned = new ArrayList<RdsSnapshot>(getAllKualiRdsSnapshots());
		Set<RdsSnapshot> ownedSnapshots = instanceDAO.getAllSnapshots();
		orphaned.removeAll(ownedSnapshots);
		return orphaned;
	}
	
	
	public Map<Landscape, List<RdsSnapshot>> getAllOrphanedKualiRdsSnapshotssGroupedByBaseline(RdsInstanceDAO instanceDAO) {
		Map<Landscape, List<RdsSnapshot>> rdsSnapshots = new TreeMap<Landscape, List<RdsSnapshot>>(new Comparator<Landscape>() {
			@Override public int compare(Landscape key1, Landscape key2) {
				return key1.getOrder() - key2.getOrder();
			}			
		});
		
		List<RdsSnapshot> orphaned = getAllOrphanedKualiRdsSnapshots(instanceDAO);
		
		for(Landscape landscape : Landscape.values()) {
			List<RdsSnapshot> snapshots = new ArrayList<RdsSnapshot>();
			for(RdsSnapshot snapshot : orphaned) {
				if(Landscape.fromAlias(snapshot.getBaseline()) != null) {
					if(landscape.is(snapshot.getBaseline())) {
						snapshots.add(snapshot);
					}
				}				
			}
			rdsSnapshots.put(landscape, snapshots);
		}
		return rdsSnapshots;
	}
	
	
	/**
	 * Return a list of kuali rds snapshots filtered according to what matches can be determined against fields set in 
	 * a "filter" RdsSnapshot instance.
	 * 
	 * @param filter The filter instance does not itself originate from any lookup, but is "borrowed" for the purpose 
	 * of consolidating filtering parameters as a single object.
	 * @return
	 */
	public List<RdsSnapshot> getKualiRdsSnapshots(RdsSnapshot filter) {
		List<RdsSnapshot> snapshots = new ArrayList<RdsSnapshot>();
		for(RdsSnapshot snapshot : getAllKualiRdsSnapshots()) {
			if(filter.getArn() != null && filter.getArn().equals(snapshot.getArn())) {
				snapshots.add(snapshot);
				continue;
			}
			if(filter.getName() != null && filter.getName().equals(snapshot.getName())) {
				snapshots.add(snapshot);
				continue;
			}
			if(filter.getBaseline() != null && ! filter.getBaseline().equals(snapshot.getBaseline())) {
				continue;
			}
			if(filter.getLandscape() != null && ! filter.getLandscape().equals(snapshot.getLandscape())) {
				continue;
			}
			if(filter.getType() != null && ! filter.getType().equals(snapshot.getType())) {
				continue;
			}
			if(filter.getRdsInstanceArn() != null && ! filter.getRdsInstanceArn().equals(snapshot.getRdsInstanceArn())) {
				continue;
			}
			if(filter.getRdsInstanceName() != null && ! filter.getRdsInstanceName().equals(snapshot.getRdsInstanceName())) {
				continue;
			}
			snapshots.add(snapshot);
		}
		return snapshots;
	}

	@Override
	public Collection<?> getResources() {
		return getAllKualiRdsSnapshots();
	}
	
	private static RdsSnapshot getFilter(NamedArgs namedArgs) {
		return (RdsSnapshot) new RdsSnapshot()
				.setRdsInstance(new RdsInstance()
						.setArn(namedArgs.get("rdsInstanceArn"))
						.setName(namedArgs.get("rdsInstanceName")))
				.setType(namedArgs.get("type"))
				.setArn(namedArgs.get("arn"))
				.setName(namedArgs.get("name"))
				.setBaseline(namedArgs.get("baseline"))
				.setLandscape(namedArgs.get("landscape"));
	}
	
	public static void main(String[] args) {
		NamedArgs namedArgs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		if( ! namedArgs.has("task")) {
			System.out.println("Missing: task parameter");
			return;
		}
		String task = namedArgs.get("task").toLowerCase();
		
		List<RdsSnapshot> snapshots = null;
		RdsSnapshotDAO dao = new RdsSnapshotDAO(AWSCredentials.getInstance(namedArgs));
		
		switch(task) {
			case "get":
				snapshots = dao.getKualiRdsSnapshots(getFilter(namedArgs));
				break;
			case "orphans":
				List<RdsSnapshot> orphaned = dao.getKualiRdsSnapshots(getFilter(namedArgs));
				snapshots = dao.getAllOrphanedKualiRdsSnapshots();
				break;
		}
		
		for(RdsSnapshot snapshot : snapshots) {
			System.out.println(snapshot);
		}		
	}
}
