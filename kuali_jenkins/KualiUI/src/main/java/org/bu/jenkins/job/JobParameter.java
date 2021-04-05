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
	private Map<String, String> allParameters;
	
	public JobParameter(Object name, Map<String, String> otherParameters) {
		super();
		this.name = name.toString();
		this.allParameters = otherParameters;
	}
	
	private String getNameString(Object nameObj) {
		if(nameObj == null) return null;
		return nameObj.toString();
	}
	
	public String getValue() {
		return getOtherParmValue(name);
	}
	
	public void setValue(String value) {
		allParameters.put(name, value);
	}
	
	public boolean hasValue(String value) {
		if(getValue() == null) return false;
		if(getValue().equalsIgnoreCase(value)) return true;
		return false;
	}
	
	public boolean hasAnyValue(String...values) {
		for(String value : values) {
			if(hasValue(value)) {
				return true;
			}
		}
		return false;
	}
	
	public boolean isChecked() {
		return "true".equalsIgnoreCase(getValue());
	}
	
	public boolean isChecked(Object nameObj) {
		return otherParmSetWith(nameObj, "true");
	}
	
	public boolean isBlank() {
		return _isBlank(getValue());
	}
	
	public boolean otherParmSetWith(Object nameObj, String value) {
		String name = getNameString(nameObj);
		if(anyBlank(name, value)) {
			return false;
		}
		for (Entry<String, String> set : allParameters.entrySet()) {
			if(set.getKey().equalsIgnoreCase(name)) {
				if(set.getValue() == null || set.getValue().isBlank()) {
					return false;
				}
				return value.equalsIgnoreCase(set.getValue().trim());
			}
		}
		return false;
	}
	
	public boolean otherParmNotSetWith(Object nameObj, String value) {
		return ! otherParmSetWith(nameObj, value);
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
		if(_isBlank(name)) {
			return false;
		}
		for (Entry<String, String> set : allParameters.entrySet()) {
			if(set.getKey().equalsIgnoreCase(name)) {
				return _isBlank(set.getValue());
			}
		}
		return true;
	}

	public boolean otherParmSetButNotEqualTo(Object nameObj, String value) {
		String name = getNameString(nameObj);
		if(anyBlank(name, value)) {
			return false;
		}
		for (Entry<String, String> set : allParameters.entrySet()) {
			if(set.getKey().equalsIgnoreCase(name)) {
				return ! value.equalsIgnoreCase(set.getValue().trim());
			}
		}
		return false;
	}
	
	public String getOtherParmValue(Object nameObj) {
		String name = getNameString(nameObj);
		if(_isBlank(name)) {
			return null;
		}
		for (Entry<String, String> set : allParameters.entrySet()) {
			if(set.getKey().equalsIgnoreCase(name)) {
				return set.getValue();
			}
		}
		return null;		
	}
	
	private boolean _isBlank(Object obj) {
		if(obj == null) return true;
		if(String.valueOf(obj).isBlank()) return true;
		return false;
	}
	
	private boolean anyBlank(Object...objs) {
		for (Object obj : objs) {
			if(_isBlank(obj)) return true;
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
		return allParameters;
	}

	public void setParameterMap(Map<String, String> otherParameters) {
		this.allParameters = otherParameters;
	}
}
