package org.bu.jenkins.mvc.model;

import java.time.Instant;

import software.amazon.awssdk.services.rds.model.DBSnapshot;

public class RdsSnapshot extends AbstractAwsResource implements Comparable<RdsSnapshot> {
	
	private DBSnapshot snapshot;
	private AbstractAwsResource rdsInstance = new RdsInstance();
	private Instant creationTime;
	private String type;
	
	public RdsSnapshot() {
		super();
	}
	public RdsSnapshot(DBSnapshot snapshot) {
		this.snapshot = snapshot;
		super.arn = snapshot.dbSnapshotArn();
		super.name = snapshot.dbSnapshotIdentifier();
		for(software.amazon.awssdk.services.rds.model.Tag tag : snapshot.tagList()) {
			super.putTag(tag.key(), tag.value());
		}
		this.creationTime = snapshot.snapshotCreateTime();
		this.type = snapshot.snapshotType();
		this.rdsInstance = new RdsInstance(snapshot.dbiResourceId());
	}
	public RdsSnapshot(AbstractAwsResource rdsInstance, Instant creationTime, String arn, String type) {
		super(arn);
		this.rdsInstance = rdsInstance;
		this.creationTime = creationTime;
		this.type = type;
	}
	public RdsSnapshot(String arn) {
		super(arn);
	}
	public RdsSnapshot(String arn, String landscape, String baseline) {
		super(arn, landscape, baseline);
	}
	public DBSnapshot getDBSnapshot() {
		return snapshot;
	}
	public String getCreationTime() {
		return creationTime.toString();
	}
	public RdsSnapshot setCreationTime(Instant creationTime) {
		this.creationTime = creationTime;
		return this;
	}
	public String getType() {
		return type;
	}
	public RdsSnapshot setType(String type) {
		this.type = type;
		return this;
	}
	public AbstractAwsResource getRdsInstance() {
		return rdsInstance;
	}
	public RdsSnapshot setRdsInstance(AbstractAwsResource rdsInstance) {
		this.rdsInstance = rdsInstance;
		return this;
	}
	public String getRdsInstanceArn() {
		if(rdsInstance == null)
			return null;
		return rdsInstance.getArn();
	}
	@Override
	public String getName() {
		String name = super.getName();
		if(name == null && super.arn != null) {
			String[] parts = arn.split(":");
			name = parts[parts.length - 1];
		}
		return name;
	}
	public boolean hasBaselineInName() {
		return getBaselineFromName() != null;
	}
	public Landscape getBaselineFromName() {
		return Landscape.baselineRecognizedInString(getName());
	}
	public String getRdsInstanceName() {
		if(rdsInstance == null)
			return null;
		return rdsInstance.getName();
	}
	@Override
	public String toString() {
		StringBuilder builder = new StringBuilder();
		builder.append("RdsSnapshot [creationTime=").append(creationTime).append(", type=").append(type)
				.append(", arn=").append(arn).append(", name=").append(name).append(", getRdsInstanceArn()=")
				.append(getRdsInstanceArn()).append(", getRdsInstanceName()=").append(getRdsInstanceName())
				.append(", getBaseline()=").append(getBaseline()).append(", getLandscape()=").append(getLandscape())
				.append("]");
		return builder.toString();
	}
	@Override
	public int hashCode() {
		final int prime = 31;
		int result = 1;
		result = prime * result + ((arn == null) ? 0 : arn.hashCode());
		result = prime * result + ((type == null) ? 0 : type.hashCode());
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
		RdsSnapshot other = (RdsSnapshot) obj;
		if(arn == null)
			return false;
		if(arn.equals(other.arn))
			return true;
		return false;
	}
	/**
	 * Compare by reverse creation date order
	 */
	@Override
	public int compareTo(RdsSnapshot snapshot) {
		if(this.creationTime != null && snapshot.creationTime != null) {
			if(this.creationTime.isAfter(snapshot.creationTime)) return -1;
			if(this.creationTime.isBefore(snapshot.creationTime)) return 1;
		}
		return 0;
	}
}