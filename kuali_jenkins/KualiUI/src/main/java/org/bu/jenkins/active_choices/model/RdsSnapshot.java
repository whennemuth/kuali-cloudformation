package org.bu.jenkins.active_choices.model;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;

import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.NamedArgs;

import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.awscore.exception.AwsServiceException;
import software.amazon.awssdk.core.exception.SdkClientException;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.rds.RdsClient;
import software.amazon.awssdk.services.rds.model.DBSnapshot;
import software.amazon.awssdk.services.rds.model.DescribeDbSnapshotsRequest;
import software.amazon.awssdk.services.rds.model.DescribeDbSnapshotsResponse;

/**
 * Represents an RDS instance, acquired directly by ARN or indirectly by landscape tag,
 * with a focus on gathering and subdividing the snapshots in that instance.
 * 
 * @author wrh
 *
 */
public class RdsSnapshot extends AbstractModel {

	private String landscape;
	private String rdsInstanceARN;
	private List<SnapshotSummary> snapshots;
	
	public RdsSnapshot(AWSCredentials credentials) {
		super(credentials);
	}
	
	public RdsSnapshot(AwsCredentialsProvider provider) {
		super(provider);
	}

	public Map<String, String> getDeployedKualiRdsInstancesByLandscape() {
		return new LandscapeList(provider).getDeployedKualiRdsInstancesByLandscape();
		
	}
	
	/**
	 * Make the aws api calls to get the snapshot data.
	 */
	private void loadSnapshots() {
		if(snapshots == null) {
			snapshots = new ArrayList<SnapshotSummary>();
			if(hasValue(rdsInstanceARN)) {
				snapshots.addAll(getRdsSnapshots(rdsInstanceARN));
			}
			else if(hasValue(landscape)) {
				snapshots.addAll(getRdsSnapshotsForLandscape(landscape));
			}
		}
	}
	
	/**
	 * Get the snapshots for the rds instance identified as having the specified landscape tag
	 * @param landscape
	 * @return
	 */
	private List<SnapshotSummary>  getRdsSnapshotsForLandscape(String landscape) {
		List<SnapshotSummary> snapshots = new ArrayList<SnapshotSummary>();
		for(Entry<String, String> rdsInstance : getDeployedKualiRdsInstancesByLandscape().entrySet()) {
			if(landscape.equalsIgnoreCase(rdsInstance.getValue())) {
				return getRdsSnapshots(rdsInstance.getKey());
			}
		}
		return snapshots;
	}
	
	/**
	 * Get the snapshots for the rds instance identified by the specified ARN
	 * @param rdsInstanceARN
	 * @return
	 */
	private List<SnapshotSummary> getRdsSnapshots(String rdsInstanceARN) {
		List<SnapshotSummary> snapshots = new ArrayList<SnapshotSummary>();
		
		try {
			DescribeDbSnapshotsRequest request = DescribeDbSnapshotsRequest.builder()
					.dbInstanceIdentifier(rdsInstanceARN)
					.build();
			
			RdsClient client = RdsClient.builder()
					.region(Region.US_EAST_1)
					.credentialsProvider(provider)
					.httpClient(ApacheHttpClient.builder().build())
					.build();
			
			DescribeDbSnapshotsResponse response = client.describeDBSnapshots(request);
			
			if(response.hasDbSnapshots()) {
				for(DBSnapshot snapshot : response.dbSnapshots()) {
					if("available".equalsIgnoreCase(snapshot.status())) {
						snapshots.add(new SnapshotSummary(
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
		
		return snapshots;
	}
	
	/**
	 * Get all snapshots for the RDS instance that were manually created.
	 * 
	 * @return
	 */
	public List<SnapshotSummary> getManuallyCreated() {
		loadSnapshots();
		List<SnapshotSummary> manual = new ArrayList<SnapshotSummary>(snapshots);
		manual.removeIf(snapshot -> (!snapshot.getType().equalsIgnoreCase("manual")));
		return manual;
	}
	
	/**
	 * Get all snapshots for the RDS instance that were automatically created at regular intervals configured by the instance.
	 * 
	 * @return
	 */
	public List<SnapshotSummary> getAutomaticallyCreated() {
		loadSnapshots();
		List<SnapshotSummary> manual = new ArrayList<SnapshotSummary>(snapshots);
		manual.removeIf(snapshot -> (!snapshot.getType().equalsIgnoreCase("automated")));
		return manual;
	}
	
	private boolean hasValue(Object obj) {
		if(obj == null)
			return false;
		if(obj.toString().isBlank())
			return false;
		return true;
	}
	
	public String getLandscape() {
		return landscape;
	}
	public RdsSnapshot setLandscape(String landscape) {
		this.landscape = landscape;
		return this;
	}
	public String getRdsInstanceARN() {
		return rdsInstanceARN;
	}
	public RdsSnapshot setRdsInstanceARN(String rdsInstanceARN) {
		this.rdsInstanceARN = rdsInstanceARN;
		return this;
	}

	public static class SnapshotSummary {
		private Instant creationTime;
		private String arn;
		private String type;
		public SnapshotSummary(Instant creationTime, String arn, String type) {
			super();
			this.creationTime = creationTime;
			this.arn = arn;
			this.type = type;
		}
		public String getCreationTime() {
			return creationTime.toString();
		}
		public String getArn() {
			return arn;
		}
		public String getType() {
			return type;
		}
		@Override
		public String toString() {
			StringBuilder builder = new StringBuilder();
			builder.append("SnapshotSummary [getCreationTime()=").append(getCreationTime()).append(", getArn()=")
					.append(getArn()).append(", getType()=").append(getType()).append("]");
			return builder.toString();
		}
	}

	public static void main(String[] args) {
		NamedArgs namedArgs = new NamedArgs(args);
		RdsSnapshot rdsList = new RdsSnapshot(new AWSCredentials(namedArgs)).setLandscape(namedArgs.get("landscape"));
		System.out.println("--------------------------------------------");
		System.out.println("          Manually Created");
		System.out.println("--------------------------------------------");
		for(SnapshotSummary snapshot : rdsList.getManuallyCreated()) {
			System.out.println(snapshot.toString());
		}
		System.out.println("--------------------------------------------");
		System.out.println("          Automatically Created");
		System.out.println("--------------------------------------------");
		for(SnapshotSummary snapshot : rdsList.getAutomaticallyCreated()) {
			System.out.println(snapshot.toString());
		}
	}

}
