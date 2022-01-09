package org.bu.jenkins.job.kuali;

import java.text.SimpleDateFormat;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

import org.bu.jenkins.dao.RdsInstanceDAO;
import org.bu.jenkins.dao.RdsSnapshotDAO;
import org.bu.jenkins.dao.StackDAO;
import org.bu.jenkins.mvc.controller.job.kuali.StackCreateDeleteController;
import org.bu.jenkins.mvc.model.AbstractAwsResource;
import org.bu.jenkins.mvc.model.Landscape;
import org.bu.jenkins.mvc.model.RdsInstance;
import org.bu.jenkins.mvc.model.RdsSnapshot;

import software.amazon.awssdk.services.cloudformation.model.Stack;
import software.amazon.awssdk.services.cloudformation.model.StackSummary;
import software.amazon.awssdk.services.cloudformation.model.Tag;

/**
 * Test harness for the stack create/update/delete jenkins job.
 * The main feature is mocked data replaces the need for real cloud resources to exist 
 * in order to have fields/tables/lists populate.
 * 
 * @author wrh
 *
 */
public class StackCreateDeleteTest {

	public static final long DAY = 1000 * 60 * 60 * 24;
	
	public static int counter = 1;
	
	public static void putStackMock(int daysAgo, Landscape baseline, String landscape) {
		
		List<Tag> tags = new ArrayList<Tag>();
		
		tags.add(Tag.builder().key("Category").value("application").build());
		tags.add(Tag.builder().key("Service").value("research-administration").build());
		tags.add(Tag.builder().key("Function").value("kuali").build());
		tags.add(Tag.builder().key("Baseline").value(baseline.getId()).build());
		tags.add(Tag.builder().key("Landscape").value(landscape).build());
		
		String id = getTimeStr(daysAgo);
		
		Stack stack = Stack.builder()
				.stackId(String.format("myStackId_%s", id))
				.creationTime(getInstant(daysAgo))
				.description(String.format("My stack description %s", id))
				.stackName(String.format("My Stack %s", id))
				.stackStatus("CREATE_COMPLETE")
				.tags(tags)
				.build();
		
		StackSummary summary = StackSummary.builder()
				.stackId(stack.stackId())
				.parentId(stack.stackId())
				.creationTime(getInstant(daysAgo))
				.rootId(stack.stackId())
				.stackName(stack.stackName())
				.stackStatus("CREATE_COMPLETE").build();
		
		StackDAO.CACHE.put(stack);
		
		StackDAO.CACHE.put(summary);
		
		StackDAO.CACHE.setFlushable(false);
	}
	
	public static void putRdsMock(Landscape baseline, String landscape) {
				
		RdsInstance rds = (RdsInstance) new RdsInstance("rdsArn1")
				.putTag("Service", "research-administration")
				.putTag("Function", "kuali")
				.putTag("Landscape", landscape)
				.putTag("Baseline", baseline.getId());
		
		for(int i=1 ; i<=3; i++) {
			RdsSnapshot snapshot = getSnapshot(rds, counter++, "manual", null, null);
			rds.putSnapshot(snapshot);
			RdsSnapshotDAO.STANDARD_SNAPSHOT_CACHE.put(snapshot);
		}
		
		for(int i=1 ; i<=10; i++) {
			RdsSnapshot snapshot = getSnapshot(rds, counter++, "automated", null, null);
			rds.putSnapshot(snapshot);
			RdsSnapshotDAO.STANDARD_SNAPSHOT_CACHE.put(snapshot);
		}
		
		RdsInstanceDAO.CACHE.put(rds);
		
		RdsInstanceDAO.CACHE.setFlushable(false);
	}
	
	public static void putOrphanedSnapshotMock(Landscape baseline, String landscape) {
		RdsSnapshot snapshot = getSnapshot(null, counter++, "orphaned", baseline, landscape);
		RdsSnapshotDAO.STANDARD_SNAPSHOT_CACHE.put(snapshot);
		RdsSnapshotDAO.STANDARD_SNAPSHOT_CACHE.setFlushable(false);
	}
	
	public static void putSharedSnapshotMock(String landscape) {
		RdsSnapshot snapshot = getSnapshot(null, counter++, "shared", null, landscape);
		RdsSnapshotDAO.SHARED_SNAPSHOT_CACHE.put(snapshot);
		RdsSnapshotDAO.SHARED_SNAPSHOT_CACHE.setFlushable(false);		
	}
	
	private static String getTimeStr(int daysAgo) {
		Long time = getTime(daysAgo);
		return new SimpleDateFormat("yyyy-MM-EEE-kk-mm-ss-SSS").format(time);
	}
	
	private static RdsSnapshot getSnapshot(AbstractAwsResource rds, int daysAgo, String type, Landscape baseline, String landscape) {
		Long time = getTime(daysAgo);
		Instant instant = Instant.ofEpochMilli(time);
		String landscapeInjection = "";
		String typeInjection = "automated".equalsIgnoreCase(type) ? "rds:" : "";
		if("shared".equalsIgnoreCase(type) && landscape != null) {
			landscapeInjection = String.format("-%s", landscape.toLowerCase());
		}
		String name = String.format("%srdsSnapshotArn%s_%s", typeInjection, landscapeInjection, getTimeStr(daysAgo));
		String arn = String.format(
			"arn:aws:rds:%s>:%s:snapshot:%s", 
			"us-east-1",
			"770203350335",
			name);
		RdsSnapshot snapshot = new RdsSnapshot(rds, instant, arn, type);
		String baselineStr = baseline == null ? null : baseline.getId();
		return (RdsSnapshot) snapshot.setBaseline(baselineStr).setLandscape(landscape);
	}

	private static Long getTime(int daysAgo) {
		return System.currentTimeMillis() - daysAgo * DAY;
	}

	private static Instant getInstant(int daysAgo) {
		if(daysAgo == 0) return Instant.now();
		return Instant.ofEpochMilli(System.currentTimeMillis() - daysAgo * DAY);
	}
	
	public static void main(String[] args) {
		
		putStackMock(0, Landscape.CI, "chopped-liver");
		
		putRdsMock(Landscape.CI, "ci");
		putRdsMock(Landscape.STAGING, "stg");
		putRdsMock(Landscape.CI, "chopped-liver");

		putOrphanedSnapshotMock(Landscape.CI, "ci");
		putOrphanedSnapshotMock(Landscape.CI, "chopped-liver2");
		putOrphanedSnapshotMock(Landscape.STAGING, "stg");
		putOrphanedSnapshotMock(Landscape.STAGING, "chopped-liver3");
		
		putSharedSnapshotMock("ci");
		putSharedSnapshotMock("chopped-liver4");
		putSharedSnapshotMock("stg");
		putSharedSnapshotMock("chopped-liver5");
		
		StackCreateDeleteController.main(args);
	}
}
