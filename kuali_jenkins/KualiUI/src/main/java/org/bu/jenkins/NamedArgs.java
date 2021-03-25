package org.bu.jenkins;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

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
			String[] parts = arg.split("=");
			if(parts.length > 1) {
				namedArgs.put(parts[0].trim().toLowerCase(), parts[1].trim());
			}
			else {
				unamedArgs.add(parts[0]);
			}
		}
		loggingStarter.start(this);
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
	
	public Integer getInt(String key) {
		if(key == null)
			return null;
		return Integer.valueOf(get(key));
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
