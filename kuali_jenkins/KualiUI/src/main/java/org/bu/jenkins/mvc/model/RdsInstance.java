package org.bu.jenkins.mvc.model;

import java.util.HashSet;
import java.util.Iterator;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;

public class RdsInstance extends AbstractAwsResource {
	
	private Logger logger = LogManager.getLogger(RdsInstance.class.getName());

	private Set<RdsSnapshot> snapshots;
	
	public RdsInstance() {
		super();
	}
	public RdsInstance(String arn) {
		super(arn);
	}	
	public RdsInstance(String arn, Map<String, String> tags) {
		super(arn, tags);
	}	
	public RdsInstance(String arn, String landscape, String baseline) {
		super(arn, landscape, baseline);
	}
	
	public Set<RdsSnapshot> getSnapshots() {
		if(snapshots == null)
			return new HashSet<RdsSnapshot>();
		return snapshots;
	}
	
	/**
	 * Get all snapshots for the RDS instance that were automatically created at regular intervals configured by the instance.
	 * 
	 * @return
	 */
	public Set<RdsSnapshot> getAutomaticallyCreatedSnapshots() {
		EntryMessage m = logger.traceEntry("getAutomaticallyCreatedSnapshots()");
		Set<RdsSnapshot> manual = new TreeSet<RdsSnapshot>(getSnapshots());
		manual.removeIf(snapshot -> (!snapshot.getType().equalsIgnoreCase("automated")));
		logger.traceExit(m);
		return manual;
	}
	
	/**
	 * Get all snapshots for the RDS instance that were manually created.
	 * 
	 * @return
	 */
	public Set<RdsSnapshot> getManuallyCreatedSnapshots() {
		EntryMessage m = logger.traceEntry("getManuallyCreatedSnapshots()");
		Set<RdsSnapshot> manual = new TreeSet<RdsSnapshot>(getSnapshots());
		manual.removeIf(snapshot -> (!snapshot.getType().equalsIgnoreCase("manual")));
		logger.traceExit(m);
		return manual;
	}

	public AbstractAwsResource setSnapshots(Set<RdsSnapshot> snapshots) {
		EntryMessage m = logger.traceEntry("setSnapshots(snapshots.size()={})", snapshots==null ? "null" : snapshots.size());
		if(snapshots == null || snapshots.isEmpty()) {
			logger.traceExit(m, this.getArn());
			return this;
		}
		for(RdsSnapshot snapshot: snapshots) {
			putSnapshot(snapshot);
		}
		logger.traceExit(m, this.getArn());
		return this;
	}
	
	public AbstractAwsResource putSnapshot(RdsSnapshot snapshot) {
		EntryMessage m = logger.traceEntry("putSnapshot(snapshot={})", snapshot==null ? "null" : snapshot.getArn());
		if(snapshot == null) {
			logger.traceExit(m, this.getArn());
			return this;
		}
		if(this.snapshots == null)
			this.snapshots = new HashSet<RdsSnapshot>();
		snapshot.setRdsInstance(this);
		this.snapshots.add(snapshot);
		logger.traceExit(m, this.getArn());
		return this;
	}
	
	public boolean snapshotsLoaded() {
		return this.snapshots != null;
	}

	@Override
	public String toString() {
		String offset="   ";
		String indent="\n"+offset;
		
		StringBuilder builder = new StringBuilder();
		builder.append("RdsInstance [getArn()=").append(getArn()).append(", getLandscape()=").append(getLandscape())
				.append(", getBaseline()=").append(getBaseline());
		
		builder.append(", tags=[").append(indent);
		for (Iterator<String> iterator = tags.keySet().iterator(); iterator.hasNext();) {
			String tagname = iterator.next();
			builder.append(tagname).append(" = ").append(tags.get(tagname));
			builder.append(iterator.hasNext() ? indent : "\n],");
		}
		
		builder.append("manual snapshots=[").append(getManuallyCreatedSnapshots().isEmpty() ? "]," : indent);
		for (Iterator<RdsSnapshot> iterator = getManuallyCreatedSnapshots().iterator(); iterator.hasNext();) {
			builder.append(iterator.next());
			builder.append(iterator.hasNext() ? indent : "\n],");
		}
		
		builder.append("automatic snapshots=[").append(getAutomaticallyCreatedSnapshots().isEmpty() ? "]," : indent);
		for (Iterator<RdsSnapshot> iterator = getAutomaticallyCreatedSnapshots().iterator(); iterator.hasNext();) {
			builder.append(iterator.next());
			builder.append(iterator.hasNext() ? indent : "\n]");
		}

		return builder.toString();
	}

	@Override
	public int hashCode() {
		final int prime = 31;
		int result = 1;
		result = prime * result + ((arn == null) ? 0 : arn.hashCode());
		return result;
	}

	@Override
	public boolean equals(Object obj) {
		if (this == obj)
			return true;
		if (obj == null)
			return false;
		if (getClass() != obj.getClass())
			return false;
		AbstractAwsResource other = (AbstractAwsResource) obj;
		if (arn == null) {
			if (other.arn != null)
				return false;
		} else if (!arn.equals(other.arn))
			return false;
		return true;
	}
	
}
