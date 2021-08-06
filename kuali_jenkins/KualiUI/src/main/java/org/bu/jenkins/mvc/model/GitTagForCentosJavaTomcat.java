package org.bu.jenkins.mvc.model;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * This class is used to evaluate the tag any one of the centos7-java-tomcat images.
 * The tag is a concatenation of the java version and usually the tomcat version.
 * Also provided is the sorting logic to ensure the tags that reflect the later versions of java, then tomcat "rise to the top" of the list.
 * 
 * EXAMPLE TAGS:
 *  - java8-tomcat8.5.34
 *  - java11-tomcat8.5.34
 *  - tomcat8.5
 *  - tomcat7
 * 
 * @author wrh
 *
 */
public class GitTagForCentosJavaTomcat implements Comparable<GitTagForCentosJavaTomcat> {

	private String image;
	private String tag;
	private Version javaVersion;
	private Version tomcatVersion;
	
	public GitTagForCentosJavaTomcat(String tag) {
		if(isBlank(tag)) return;
		if(tag.contains(":")) {
			// tag is really a full image name ending in a tag after a colon.
			String[] parts = tag.split(":");
			this.tag = parts[parts.length-1];
			this.image = tag;
		}
		else {
			this.tag = tag;
		}
	}

	public Version getJavaVersion() {
		if(this.javaVersion == null) {
			this.javaVersion = new Version(getVersion("java"));
		}
		return javaVersion;
	}
	
	public Version getTomcatVersion() {
		if(this.tomcatVersion == null) {
			this.tomcatVersion = new Version(getVersion("tomcat"));
		}
		return this.tomcatVersion;
	}
	
	private String getVersion(String type) {
		String version = "0";
		if( ! isBlank(this.tag)) {
			String regex = String.format(".*%s([\\d\\.]+).*", type);
			Pattern p = Pattern.compile(regex, Pattern.CASE_INSENSITIVE);
			Matcher m = p.matcher(this.tag);
			if(m.matches()) {
				if(m.groupCount() > 0) {
					try {
						version = m.group(1);
					}
					catch (NumberFormatException e) {
						return version;
					}
				}						
			}
		}
		
		return version;		
	}

	@Override
	public int compareTo(GitTagForCentosJavaTomcat tag) {
		if(tag.getJavaVersion().compareTo(this.getJavaVersion()) == 0) {
			return tag.getTomcatVersion().compareTo(this.getTomcatVersion());
		}
		return tag.getJavaVersion().compareTo(this.getJavaVersion());
	}	
	
	/**
	 * Given a version string like "8.5.34", this class provides functionality to compare that version to 
	 * another version such that the first of the two whose nth segment is greater than the others nth segment
	 * is the greater version, where "segment" is an integer between "." characters.
	 * EXAMPLES:
	 *   8.5.34 > 8.4.36
	 *   8.6 > 8.5.34
	 *   
	 * @author wrh
	 *
	 */
	public static class Version implements Comparable<Version> {
		private List<Integer> parts = new ArrayList<Integer>();
		public Version(String version) {
			for(String part : version.split("\\."))	{
				parts.add(Integer.parseInt(part));
			}			
		}
		@Override public int compareTo(Version v) {
			for(int i=0; ; i++) {
				Integer part1 = getPart(i);
				Integer part2 = v.getPart(i);
				if(part1 == part2) {
					if(part1 < 0) {
						return 0;
					}
				}
				else {
					return part1.compareTo(part2);
				}
			}
		}
		public int getPart(int i) {
			try {
				return parts.get(i);
			} 
			catch (IndexOutOfBoundsException e) {
				return -1;
			}
		}
	}
	
	public String getImage() {
		return image == null ? "" : image;
	}

	public String getTag() {
		return tag;
	}

	@Override
	public String toString() {
		StringBuilder builder = new StringBuilder();
		builder.append("JavaTomcatTag [tag=").append(tag).append(", getJavaVersion()=").append(getJavaVersion())
				.append(", getTomcatVersion()=").append(getTomcatVersion()).append("]");
		return builder.toString();
	}

	@Override
	public int hashCode() {
		final int prime = 31;
		int result = 1;
		result = prime * result + ((tag == null) ? 0 : tag.hashCode());
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
		GitTagForCentosJavaTomcat other = (GitTagForCentosJavaTomcat) obj;
		if (tag == null) {
			if (other.tag != null)
				return false;
		} else if (!tag.equals(other.tag))
			return false;
		return true;
	}

	private boolean isBlank(Object o) {
		if(o == null) return true;
		if(o.toString().isBlank()) return true;
		return false;
	}
	
	public static void main(String[] args) {
		
		Set<GitTagForCentosJavaTomcat> tags = new TreeSet<GitTagForCentosJavaTomcat>();
		
		tags.add(new GitTagForCentosJavaTomcat("tomcat8.5"));
		tags.add(new GitTagForCentosJavaTomcat("tomcat7"));
		tags.add(new GitTagForCentosJavaTomcat("java8-tomcat8.5.34"));
		tags.add(new GitTagForCentosJavaTomcat("java12-tomcat9.0"));
		tags.add(new GitTagForCentosJavaTomcat("java11-tomcat8.5.34"));
		tags.add(new GitTagForCentosJavaTomcat("java11.2.5"));
		tags.add(new GitTagForCentosJavaTomcat("bogus"));
		
		tags.forEach((t) -> {
			System.out.println(t.getTag());
		});
	}
}
