package org.bu.jenkins.util;

import java.util.Iterator;
import java.util.Set;
import java.util.TreeSet;

/**
 * The Coeus maven module uses a version tag that must match the following convention:
 *    YYMM.xxxx (Y=year, M=month, x=iteration).
 * This class wraps a string value representing such a version and provides comparison 
 * logic for sorting by the date indicated in descending order.
 * 
 * @author wrh
 *
 */
public class ComparableMavenVersion implements Comparable<ComparableMavenVersion> {

	private String version;
	private boolean invalid = false;
	
	private Integer year = 0;
	private Integer month = 0;
	private Integer iteration = 0;

	public ComparableMavenVersion(String version) {
		this.version = version;
		initialize(version);
	}
	
	private void initialize(String version) {
		String[] parts = version.split("\\.");
		if(parts.length == 2) {
			if( ! parts[0].matches("\\d{1,4}")) {
				invalid = true;
				return;
			}
			parts[0] = parts[0] + "0000".substring(parts[0].length());
			year = Integer.valueOf(parts[0].substring(0, 2));
			month = Integer.valueOf(parts[0].substring(2, 4));
			iteration = Integer.valueOf(parts[1]);
		}
		else if(parts.length == 1) {
			initialize(version + ".0000");
		}
		else {
			invalid = true;
		}
	}

	@Override
	public int compareTo(ComparableMavenVersion version) {
		if(this.invalid && version.invalid) {
			return 0;
		}
		else if(this.invalid) {
			return 1;
		}
		else if(version.invalid) {
			return -1;
		}
		else {
			if(year == version.year) {
				if(month == version.month) {
					if(iteration == version.iteration) {
						return 0;
					}
					else {
						return iteration > version.iteration ? -1 : 1;
					}
				}
				else {
					return month > version.month ? -1 : 1;
				}
			}
			else {
				return year > version.year ? -1 : 1;
			}
		}
	}

	@Override
	public String toString() {
		StringBuilder builder = new StringBuilder();
		builder.append("ComparableMavenVersion [version=").append(version).append(", year=").append(year)
				.append(", month=").append(month).append(", iteration=").append(iteration).append("]");
		return builder.toString();
	}

	public static void main(String[] args) {
		String [] versions = new String[] {
			"0701.0006",
			"1234.0000",
			"1809.0027",
			"0000.0000",
			"garbage",
			"1903.0032",
			"1234.5678",
			"1234",
			"1234.0001"
		};
		
		Set<ComparableMavenVersion> set = new TreeSet<ComparableMavenVersion>();
		for(String version : versions) {
			set.add(new ComparableMavenVersion(version));
		}
		
		for (Iterator<ComparableMavenVersion> iterator = set.iterator(); iterator.hasNext();) {
			ComparableMavenVersion mv = (ComparableMavenVersion) iterator.next();
			System.out.println(mv);
		}
	}
}
