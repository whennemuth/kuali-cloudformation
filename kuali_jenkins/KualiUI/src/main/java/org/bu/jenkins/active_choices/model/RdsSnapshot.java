package org.bu.jenkins.active_choices.model;

import java.time.Instant;

public class RdsSnapshot implements Comparable<RdsSnapshot> {
	
	private RdsInstance rdsInstance;
	private Instant creationTime;
	private String arn;
	private String type;
	
	public RdsSnapshot(RdsInstance rdsInstance, Instant creationTime, String arn, String type) {
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
	public RdsInstance getRdsInstance() {
		return rdsInstance;
	}
	public RdsSnapshot setRdsInstance(RdsInstance rdsInstance) {
		this.rdsInstance = rdsInstance;
		return this;
	}
	@Override
	public String toString() {
		StringBuilder builder = new StringBuilder();
		builder.append("RdsSnapshot [rdsInstance=").append(rdsInstance.getArn()).append(", creationTime=").append(creationTime)
				.append(", arn=").append(arn).append(", type=").append(type).append("]");
		return builder.toString();
	}
	@Override
	public int hashCode() {
		final int prime = 31;
		int result = 1;
		result = prime * result + ((arn == null) ? 0 : arn.hashCode());
		result = prime * result + ((creationTime == null) ? 0 : creationTime.hashCode());
		result = prime * result + ((rdsInstance == null) ? 0 : rdsInstance.getArn().hashCode());
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
		if (arn == null) {
			if (other.arn != null)
				return false;
		} else if (!arn.equals(other.arn))
			return false;
		if (creationTime == null) {
			if (other.creationTime != null)
				return false;
		} else if (!creationTime.equals(other.creationTime))
			return false;
		if (rdsInstance == null) {
			if (other.rdsInstance != null)
				return false;
		} else if (!rdsInstance.getArn().equals(other.rdsInstance.getArn()))
			return false;
		if (type == null) {
			if (other.type != null)
				return false;
		} else if (!type.equals(other.type))
			return false;
		return true;
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