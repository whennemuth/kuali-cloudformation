package org.bu.jenkins;

import java.util.HashMap;
import java.util.Map;
import java.util.Map.Entry;

/**
 * Extends map functionality for environment variables so that keys don't have to be equal, but must simply satisfy equalsIgnoreCase for matching.
 * @author wrh
 *
 */
public class CaseInsensitiveEnvironment implements Environment {

	private Map<String, String> env = new HashMap<String, String>();
	
	public CaseInsensitiveEnvironment() {
		this(System.getenv());
		System.out.println("CaseInsensitiveEnvironment()");
	}
	public CaseInsensitiveEnvironment(Map<String, String> env) {
		this.env.putAll(env);
		System.out.println(String.format("CaseInsensitiveEnvironment(env.size()=%s)", env==null ? "null" : env.size()));
	}

	@Override
	public boolean containsKey(String key) {
		if(env.containsKey(key)) {
			return true;
		}
		for(Entry<String, String> e : env.entrySet()) {
			if(e.getKey().equalsIgnoreCase(key)) return true;
		}
		return false;
	}

	@Override
	public String get(String key) {
		for(Entry<String, String> e : env.entrySet()) {
			if(e.getKey().equalsIgnoreCase(key)) return e.getValue();
		}
		return null;
	}

}
