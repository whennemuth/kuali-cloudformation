package org.bu.jenkins.util;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import org.bu.jenkins.util.logging.LoggingStarter;

/**
 * Utility class for organizing java arguments into mapped name/value pairs.
 * The arguments must be in a "name=value" format.
 * 
 * @author wrh
 *
 */
public class NamedArgs {

	Map<String, String> namedArgs = new HashMap<String, String>();
	Set<String> unamedArgs = new HashSet<String>();
	
	public NamedArgs(LoggingStarter loggingStarter) {
		super();
		loggingStarter.start(this);
	}
	
	public NamedArgs(LoggingStarter loggingStarter, String[] args) {
		System.out.println(String.format(
				"NamedArgs(loggingStarter%s, args=%s", 
				loggingStarter==null ? "null" : loggingStarter.hashCode(),
				args==null ? "null" : args.length));
		for(String arg : args) {
			if(arg.contains("=")) {
				namedArgs.put(
					arg.substring(0, arg.indexOf("=")).trim().toLowerCase(), 
					arg.substring(arg.indexOf("=")+1).trim());				
			}
			else {
				unamedArgs.add(arg);
			}
		}
		if(loggingStarter != null) {
			loggingStarter.start(this);
		}
	}
	
	public NamedArgs set(String key, String value) {
		if(key != null)			
			namedArgs.put(key.toLowerCase(), value);
		return this;
	}
	
	public String get(String key) {
		if(key == null)
			return null;
		return namedArgs.get(key.toLowerCase().trim());
	}
	
	public String get(String key, String defaultValue) {
		String value = get(key);
		if(value == null)
			value = defaultValue;
		return value;
	}
	
	public Map<String, String> getAllNamed() {
		return namedArgs;
	}
	
	/**
	 * Get a reduced map from namedArgs that excludes original entries whose keys are not specified in the provided key array.
	 * 
	 * @param keys
	 * @return
	 */
	public Map<String, String> getAllNamed(String[] keys) {
		Map<String, String> filtered = new HashMap<String, String>();
		if(keys == null || keys.length == 0) {
			return filtered;
		}
		for(String key : keys) {
			if(namedArgs.containsKey(key)) {
				filtered.put(key, namedArgs.get(key));
			}
		}
		return filtered;
	}
	
	public Integer getInt(String key) {
		if(key == null)
			return null;
		try {
			return Integer.valueOf(get(key));
		} 
		catch (NumberFormatException e) {
			return null;
		}
	}
	
	public Boolean getBoolean(String key) {
		if(key == null)
			return false;
		return Boolean.valueOf(String.valueOf(get(key)).toLowerCase());
	}
	
	public boolean hasNamedArgs() {
		return ! namedArgs.isEmpty();
	}

	public Set<String> getUnamedArgs() {
		return unamedArgs;
	}
	
	public boolean hasUnamedArgs() {
		return ! unamedArgs.isEmpty();
	}
	
	public boolean hasUnamedArg(String arg) {
		for(String unamed : unamedArgs) {
			if(unamed.equalsIgnoreCase(arg)) {
				return true;
			}
		}
		return false;
	}
	
	public boolean has(String key) {
		return get(key) != null;
	}
}
