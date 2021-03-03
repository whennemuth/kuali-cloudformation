package org.bu.jenkins.job;

import java.util.Map;
import java.util.Map.Entry;

/**
 * Utility class for an active choices job parameter. These job parameters are configured with the values of their 
 * neighboring parameters. Most of the functionality here provides convenient methods to test those other values.
 * Comparisons are made to be somewhat relaxed in that they can be case-insensitive for name and value,
 * and not care about bordering whitespace.
 * 
 * @author wrh
 *
 */
public class JobParameter {

	private String name;
	private Map<String, String> otherParameters;
	
	public JobParameter(Object name, Map<String, String> otherParameters) {
		super();
		this.name = name.toString();
		this.otherParameters = otherParameters;
	}
	
	private String getNameString(Object nameObj) {
		if(nameObj == null) return null;
		return nameObj.toString();
	}
	
	public boolean otherParmSetWith(Object nameObj, String value) {
		String name = getNameString(nameObj);
		if(anyBlank(name, value)) {
			return false;
		}
		for (Entry<String, String> set : otherParameters.entrySet()) {
			if(set.getKey().equalsIgnoreCase(name)) {
				return value.equalsIgnoreCase(set.getValue().trim());
			}
		}
		return false;
	}
	
	public boolean otherParmSetWithAny(Object nameObj, String...values) {
		for(String value : values) {
			if(otherParmSetWith(nameObj, value)) {
				return true;
			}
		}
		return false;
	}
	
	public boolean otherParmBlank(Object nameObj) {
		String name = getNameString(nameObj);
		if(isBlank(name)) {
			return false;
		}
		for (Entry<String, String> set : otherParameters.entrySet()) {
			if(set.getKey().equalsIgnoreCase(name)) {
				return isBlank(set.getValue());
			}
		}
		return true;
	}

	public boolean otherParmSetButNotEqualTo(Object nameObj, String value) {
		String name = getNameString(nameObj);
		if(anyBlank(name, value)) {
			return false;
		}
		for (Entry<String, String> set : otherParameters.entrySet()) {
			if(set.getKey().equalsIgnoreCase(name)) {
				return ! value.equalsIgnoreCase(set.getValue().trim());
			}
		}
		return false;
	}
	
	public String getOtherParmValue(Object nameObj) {
		String name = getNameString(nameObj);
		if(isBlank(name)) {
			return null;
		}
		for (Entry<String, String> set : otherParameters.entrySet()) {
			if(set.getKey().equalsIgnoreCase(name)) {
				return set.getValue();
			}
		}
		return null;		
	}
	
	private boolean isBlank(Object obj) {
		if(obj == null) return true;
		if(String.valueOf(obj).isBlank()) return true;
		return false;
	}
	
	private boolean anyBlank(Object...objs) {
		for (Object obj : objs) {
			if(isBlank(obj)) return true;
		}
		return false;
	}
	
	public String getName() {
		return name;
	}

	public void setName(String name) {
		this.name = name;
	}

	public Map<String, String> getParameterMap() {
		return otherParameters;
	}

	public void setParameterMap(Map<String, String> otherParameters) {
		this.otherParameters = otherParameters;
	}
}
