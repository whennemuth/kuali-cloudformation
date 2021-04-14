package org.bu.jenkins.job.kuali;

import java.text.SimpleDateFormat;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

import org.bu.jenkins.active_choices.dao.RdsDAO;
import org.bu.jenkins.active_choices.dao.StackDAO;
import org.bu.jenkins.active_choices.model.RdsInstance;
import org.bu.jenkins.active_choices.model.RdsSnapshot;

import software.amazon.awssdk.services.cloudformation.model.Stack;
import software.amazon.awssdk.services.cloudformation.model.StackSummary;
import software.amazon.awssdk.services.cloudformation.model.Tag;

public class StackCreateDeleteTestHarness {

	public static final long DAY = 1000 * 60 * 60 * 24;
	
	public static void putStackMock(int daysAgo) {
		
		List<Tag> tags = new ArrayList<Tag>();
		
		tags.add(Tag.builder().key("Category").value("application").build());
		tags.add(Tag.builder().key("Service").value("research-administration").build());
		tags.add(Tag.builder().key("Function").value("kuali").build());
		
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
	
	public static void putRdsMock(String landscape, String baseline) {
				
		RdsInstance rds = new RdsInstance("rdsArn1")
				.putTag("Service", "research-administration")
				.putTag("Function", "kuali")
				.putTag("Landscape", landscape)
				.putTag("Baseline", baseline);
		
		for(int i=0 ; i<3; i++) {
			rds.putSnapshot(getSnapshot(rds, i, "manual"));
		}
		
		for(int i=4 ; i<14; i++) {
			rds.putSnapshot(getSnapshot(rds, i, "automated"));
		}
		
		RdsDAO.CACHE.put(rds.getArn(), rds);
		
		RdsDAO.CACHE.setFlushable(false);
	}
	
	private static String getTimeStr(int daysAgo) {
		Long time = getTime(daysAgo);
		return new SimpleDateFormat("yyyy-MM-EEE-kk-mm-ss-SSS").format(time);
	}
	
	private static RdsSnapshot getSnapshot(RdsInstance rds, int daysAgo, String type) {
		Long time = getTime(daysAgo);
		Instant instant = Instant.ofEpochMilli(time);		
		String arn = String.format("rdsSnapshotArn_%s", getTimeStr(daysAgo));
		return new RdsSnapshot(rds, instant, arn, type);		
	}

	private static Long getTime(int daysAgo) {
		return System.currentTimeMillis() - daysAgo * DAY;
	}

	private static Instant getInstant(int daysAgo) {
		if(daysAgo == 0) return Instant.now();
		return Instant.ofEpochMilli(System.currentTimeMillis() - daysAgo * DAY);
	}
	
	public static void main(String[] args) {
		
		putStackMock(0);
		
		putRdsMock("ci", "ci");
		putRdsMock("stg", "stg");
		putRdsMock("chopped-liver", "ci");

		StackCreateDelete.main(args);
	}
}
